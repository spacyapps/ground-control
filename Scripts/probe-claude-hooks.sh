#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
#
# Re-measures Claude Code's hook contract after a CLI update and diffs it
# against the last accepted baseline.
#
#   ./Scripts/probe-claude-hooks.sh            run the probe, report drift
#   ./Scripts/probe-claude-hooks.sh --accept   same, then keep this run as the new baseline
#
# One real `claude -p` turn (haiku, a few cents) that runs a shell command,
# reads a file and spawns a subagent, with an observe-only hook on every event.
# The hooks come in through --settings and --setting-sources is pinned to
# `project`, so the user's own hooks (Ground Control's included) do not fire
# and no stray row reaches the panel. The probe prints nothing on stdout, so it
# returns no decision, and exits 0 always.
#
# It covers the payload shape only. The checks that need eyes or a terminal
# (red alarm, context meter after /compact, vim-mode Esc, Terminal.app escape
# codes) are in .claude/skills/verify-claude-upgrade/SKILL.md.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BASELINE="$HERE/claude-hook-keys.baseline"

# Every Claude Code hook event Ground Control registers, plus the ones it might.
EVENTS=(
  SessionStart UserPromptSubmit PreToolUse PostToolUse Notification
  PermissionRequest Stop SubagentStart SubagentStop TeammateIdle
  PreCompact SessionEnd
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/dump" "$WORK/cwd"

cat > "$WORK/hook.sh" <<'HOOK'
#!/bin/bash
# $1 = event name. Payload on stdin, one JSON object per line.
d="$(dirname "$0")/dump"
{ cat; echo; } | grep -v '^$' >> "$d/$1.jsonl" || true
env | grep '^CLAUDE' | cut -d= -f1 | sort >> "$d/$1.env" || true
exit 0
HOOK
chmod +x "$WORK/hook.sh"

# Build the --settings file: one observe-only command hook per event.
python3 -I - "$WORK" "${EVENTS[@]}" <<'PY'
import json, sys
work, events = sys.argv[1], sys.argv[2:]
hooks = {e: [{"hooks": [{"type": "command", "command": f"{work}/hook.sh {e}"}]}] for e in events}
json.dump({"hooks": hooks}, open(f"{work}/settings.json", "w"))
PY

echo "Claude Code $(claude --version)"
echo "Running one probe turn (haiku)…"
echo "probe file" > "$WORK/cwd/probe.txt"
(
  cd "$WORK/cwd"
  claude -p \
    --model haiku \
    --settings "$WORK/settings.json" \
    --setting-sources project \
    --no-session-persistence \
    --allowedTools "Bash(echo:*)" "Read" "Agent" \
    > "$WORK/claude.out" 2>&1 <<'PROMPT'
Do three things in order. 1) Run the shell command: echo probe. 2) Read probe.txt. 3) Use the Agent tool to have a subagent run: echo sub. Then reply with the word done.
PROMPT
) || { echo "claude exited non-zero:"; cat "$WORK/claude.out"; exit 1; }

# Report: keys seen per event (and the CLAUDE_* env keys hooks see), vs baseline.
python3 -I - "$WORK/dump" "$BASELINE" "$(claude --version | awk '{print $1}')" "${1:-}" <<'PY'
import glob, json, os, sys
dump, baseline, version, flag = sys.argv[1:5]

seen = {}
for path in sorted(glob.glob(f"{dump}/*.jsonl")):
    event = os.path.basename(path)[:-6]
    keys = set()
    for line in open(path):
        try:
            keys |= set(json.loads(line))
        except ValueError:
            keys.add("<unparseable>")
    seen[event] = keys
env = set()
for path in glob.glob(f"{dump}/*.env"):
    env |= set(open(path).read().split())
seen["(env)"] = env

def fmt(d):
    return "\n".join(f"{e}: {','.join(sorted(k))}" for e, k in sorted(d.items())) + "\n"

old = {}
if os.path.exists(baseline):
    for line in open(baseline):
        if line.startswith("#"): continue
        e, _, k = line.rstrip("\n").partition(": ")
        old[e] = set(filter(None, k.split(",")))

print(f"\nEvents that fired: {', '.join(e for e in seen if e != '(env)') or 'NONE'}")
if not old:
    print("No baseline yet — nothing to diff against.")
drift = False
for e in sorted(set(seen) | set(old)):
    new, was = seen.get(e), old.get(e)
    if was is None and new is not None and old:
        print(f"  NEW EVENT   {e}: {','.join(sorted(new))}"); drift = True
    elif new is None and was is not None:
        print(f"  NOT FIRED   {e} (baseline had it; may just not trigger in this turn)")
    elif new is not None and was is not None:
        if new - was: print(f"  NEW KEYS    {e}: +{','.join(sorted(new - was))}"); drift = True
        if was - new: print(f"  MISSING     {e}: -{','.join(sorted(was - new))}"); drift = True
if old and not drift:
    print("No drift: every key Ground Control saw before is still there, nothing new.")

if flag == "--accept":
    open(baseline, "w").write(f"# claude-hook-keys baseline — measured on Claude Code {version}\n" + fmt(seen))
    print(f"Baseline written for {version}: {baseline}")
elif not old:
    print("Run again with --accept to keep this as the baseline.")
PY
