#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
# install-hooks.sh — install cc-notify and register it in Claude Code settings.
#
# Grok reads ~/.claude/settings.json too (documented Claude-compat), so this
# wires up both CLIs at once. cc-notify speaks both dialects.
#
# Merges into ~/.claude/settings.json rather than overwriting: existing hooks on
# the same events are preserved (Claude Code runs every registered hook). Safe
# to re-run — an existing cc-notify registration is not duplicated.
set -euo pipefail

# ~/.groundcontrol/bin, beside ~/.claude and ~/.cursor — the company it keeps.
#
# **No spaces, and that is the whole reason.** Claude Code runs a hook command
# through /bin/sh, which word-splits: an emitter in "Application Support" was
# executed as /Users/you/Library/Application and failed on every single event.
# Quoting the registration would fix Claude and might break Cursor, which may
# exec the command directly and would then look for a path containing quote
# characters. One file, several runners, different rules — so the path simply
# has no spaces in it.
#
# Not inside the bundle either: a registration is an absolute path and bundles
# move. Not ~/bin, which belongs to the user.
# One integration at a time, or everything. Settings offers a switch per
# integration; the menu and the README still call this with no argument, which
# means "all" and behaves exactly as it always has.
TARGET="${1:-all}"

BIN_DIR="${HOME}/.groundcontrol/bin"
LEGACY="${HOME}/bin/cc-notify"
LEGACY_SUPPORT="${HOME}/Library/Application Support/GroundControl/bin"
SETTINGS="${HOME}/.claude/settings.json"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${HERE}/cc-notify"

install -d "$BIN_DIR"
install -m 0755 "$SRC" "$BIN_DIR/cc-notify"
echo "Installed cc-notify -> $BIN_DIR/cc-notify"

# The uninstaller travels with it, so removing the hooks does not depend on the
# app still being there. People trash the app first; that should not strand a
# registration pointing at a command that no longer exists.
if [ -f "${HERE}/uninstall-hooks.sh" ]; then
  install -m 0755 "${HERE}/uninstall-hooks.sh" "$BIN_DIR/uninstall-hooks.sh"
fi

# Keep the three most recent. A backup per run is right; thirty-five of them,
# which is what developing this produced, is a mess in someone else's folder.
prune() {
  ls -t "$1".bak-* 2>/dev/null | tail -n +4 | while read -r old; do rm -f "$old"; done
}

if [ "$TARGET" = "claude" ] || [ "$TARGET" = "all" ]; then
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

BACKUP="${SETTINGS}.bak-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"
echo "Backed up settings -> $BACKUP"

prune "$SETTINGS"

/usr/bin/python3 - "$SETTINGS" "$BIN_DIR/cc-notify" <<'PY'
import json, os, sys

settings_path, command = sys.argv[1], sys.argv[2]

with open(settings_path) as handle:
    settings = json.load(handle)

hooks = settings.setdefault("hooks", {})
# SessionStart/SessionEnd/SubagentStart are Grok's; harmless where unsupported,
# and SessionEnd is what lets a row vanish on quit instead of ageing out.
#
# PostToolUse carries a matcher, and is the only one that does. It exists to
# clear the alarm: answering a question emits no other event, so without it a
# row stays red from the question until the agent's next tool call. Matched to
# the question tools alone — on every tool it would merely repeat PreToolUse at
# twice the write volume.
QUESTION_TOOLS = "ask_user_question|AskUserQuestion"
events = [
    ("SessionStart", ""), ("UserPromptSubmit", ""), ("PreToolUse", ""),
    ("PostToolUse", QUESTION_TOOLS), ("Notification", ""), ("Stop", ""),
    ("SubagentStart", ""), ("SubagentStop", ""), ("SessionEnd", ""),
]
added, moved, retired = [], [], set()


def ours(hook):
    return isinstance(hook, dict) and "cc-notify" in (hook.get("command") or "")


for event, matcher in events:
    entries = hooks.setdefault(event, [])

    # Repoint rather than add. An earlier install put the emitter in ~/bin, and
    # leaving that registered alongside the new path would run two emitters into
    # the same session file — every line written twice.
    existing = [hook for entry in entries if isinstance(entry, dict)
                for hook in entry.get("hooks", []) if ours(hook)]
    if existing:
        for hook in existing:
            if hook["command"] != command:
                retired.add(hook["command"])
                hook["command"] = command
                if event not in moved:
                    moved.append(event)
        continue

    entries.append({
        "matcher": matcher,
        "hooks": [{"type": "command", "command": command}],
    })
    added.append(event)

with open(settings_path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")

# Delete exactly what was registered, rather than guessing where an older
# install put it. The registration is the only thing that knows for certain —
# and it is what we just rewrote, so nothing points at these any more.
for old_path in sorted(retired):
    if not old_path.endswith("/cc-notify") or old_path == command:
        continue
    try:
        os.remove(old_path)
        print("Removed the emitter it used to call: " + old_path)
        os.rmdir(os.path.dirname(old_path))
    except OSError:
        pass

if moved:
    print("Moved to the new location on: " + ", ".join(moved))
print("Registered on: " + (", ".join(added) if added else "(already registered, no change)"))
PY
fi

# --- opencode ----------------------------------------------------------
#
# opencode has no hook commands. Nothing in its configuration runs a script on
# an event, so the integration is a plugin: TypeScript loaded into the agent,
# handed a shell, calling the same emitter everything else calls.
#
# Two steps, and the second is the delicate one — opencode.json is a file people
# write by hand, with providers and permission tables in it, so it is merged
# rather than rewritten and backed up first.
if { [ "$TARGET" = "opencode" ] || [ "$TARGET" = "all" ]; } && [ -d "$HOME/.config/opencode" ]; then
  OC_DIR="$HOME/.config/opencode"
  install -d "$OC_DIR/plugin"
  install -m 0644 "${HERE}/opencode-plugin.ts" "$OC_DIR/plugin/groundcontrol.ts"
  echo "Installed opencode plugin -> $OC_DIR/plugin/groundcontrol.ts"

  # Whichever config it actually uses. opencode reads both spellings.
  OC_CONFIG="$OC_DIR/opencode.json"
  [ -f "$OC_CONFIG" ] || { [ -f "$OC_DIR/opencode.jsonc" ] && OC_CONFIG="$OC_DIR/opencode.jsonc"; }
  [ -f "$OC_CONFIG" ] || echo '{}' > "$OC_CONFIG"

  cp "$OC_CONFIG" "${OC_CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"
  prune "$OC_CONFIG"

  /usr/bin/python3 - "$OC_CONFIG" <<'OPENCODE'
import json, sys

path = sys.argv[1]
entry = "./plugin/groundcontrol.ts"

try:
    with open(path) as handle:
        config = json.load(handle)
except Exception:
    # A config with comments in it is not ours to rewrite. Say what to add and
    # leave the file exactly as it was.
    print("  could not parse %s — add this to its \"plugin\" array yourself:" % path)
    print("    %s" % entry)
    raise SystemExit(0)

if not isinstance(config, dict):
    print("  %s is not an object; leaving it alone" % path)
    raise SystemExit(0)

plugins = config.get("plugin")
if not isinstance(plugins, list):
    plugins = []

# Anything of ours, however it was spelled by an older install.
plugins = [p for p in plugins if not (isinstance(p, str) and "groundcontrol" in p)]
plugins.append(entry)
config["plugin"] = plugins

with open(path, "w") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
print("  registered the plugin in %s" % path)
OPENCODE
fi

# --- OpenAI Codex --------------------------------------------------------
#
# Codex reads none of the files above: its hooks live in ~/.codex/config.toml,
# registered in TOML rather than JSON, and under PascalCase event names. Its
# payloads, though, are Claude's own dialect — snake_case, same field names —
# so cc-notify needs no Codex branch beyond telling the two apart. Measured
# 2026-09-11; docs/HOOK-PAYLOADS.md.
#
# Two things here are not like the others:
#
#   1. config.toml is a file people write by hand — model choice, per-project
#      trust — so the block is appended between sentinels and only what lies
#      between them is ever rewritten.
#   2. **Codex asks permission to run hooks at all.** A one-time interactive
#      trust prompt appears at the next `codex` startup, and until it is
#      accepted no hook runs. Nothing scripted can click it; `codex exec` never
#      shows it. So this prints the instruction and stops, rather than pretending
#      the install is finished.
if { [ "$TARGET" = "codex" ] || [ "$TARGET" = "all" ]; } && [ -d "$HOME/.codex" ]; then
  CODEX_CONFIG="$HOME/.codex/config.toml"
  [ -f "$CODEX_CONFIG" ] || echo "" > "$CODEX_CONFIG"
  cp "$CODEX_CONFIG" "${CODEX_CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"
  prune "$CODEX_CONFIG"

  CODEX_BEGIN="# >>> ground-control >>>"
  CODEX_END="# <<< ground-control <<<"

  # Replace our previous block rather than appending beside it — two
  # registrations would run two emitters into one session file, writing every
  # line twice. Everything outside the sentinels is kept exactly as it was,
  # including the [hooks.state] trust record Codex writes for itself.
  awk -v b="$CODEX_BEGIN" -v e="$CODEX_END" '
    $0 == b { skip = 1 } skip != 1 { print } $0 == e { skip = 0 }
  ' "$CODEX_CONFIG" > "${CODEX_CONFIG}.gc-tmp"

  # PostToolUse carries no matcher here, unlike Claude's. It is what ends a
  # PermissionRequest alarm, and Codex's approval gate fires on any tool at
  # all — not only the question tools Claude's matcher names.
  {
    cat "${CODEX_CONFIG}.gc-tmp"
    printf '\n%s\n' "$CODEX_BEGIN"
    printf '# Ground Control. Remove with: ~/.groundcontrol/bin/uninstall-hooks.sh\n'
    for event in SessionStart UserPromptSubmit PreToolUse PostToolUse \
                 PermissionRequest Stop SubagentStart SubagentStop SessionEnd; do
      printf '\n[[hooks.%s]]\n\n[[hooks.%s.hooks]]\ntype = "command"\ncommand = "%s"\n' \
        "$event" "$event" "$BIN_DIR/cc-notify"
    done
    printf '%s\n' "$CODEX_END"
  } > "$CODEX_CONFIG"
  rm -f "${CODEX_CONFIG}.gc-tmp"

  echo "Registered Codex in ~/.codex/config.toml"
  echo "  Start \`codex\` once and ACCEPT the trust prompt — until you do, Codex"
  echo "  runs no hooks and Ground Control will show no Codex rows. Interactive"
  echo "  \`codex\` only; \`codex exec\` never offers the prompt."
fi

# --- Cursor's own agent -------------------------------------------------
#
# Composer is not a terminal process, so nothing above reaches it: Cursor reads
# its own ~/.cursor/hooks.json and nothing from ~/.claude. Its payloads are
# snake_case like Claude's, and three of its event names already normalise to
# ours, so cc-notify needs no separate emitter — only registering.
#
# Skipped silently where Cursor is not installed. Claude Code running *inside*
# Cursor's terminal is covered by the block above and needs none of this.
if { [ "$TARGET" = "cursor" ] || [ "$TARGET" = "all" ]; } && [ -d "$HOME/.cursor" ]; then
  CURSOR_HOOKS="$HOME/.cursor/hooks.json"
  if [ -f "$CURSOR_HOOKS" ]; then
    cp "$CURSOR_HOOKS" "${CURSOR_HOOKS}.bak-$(date +%Y%m%d-%H%M%S)"
    prune "$CURSOR_HOOKS"
  fi
  /usr/bin/python3 - "$CURSOR_HOOKS" "$BIN_DIR/cc-notify" <<'CURSOR'
import json, os, sys

path, command = sys.argv[1], sys.argv[2]

try:
    with open(path) as handle:
        config = json.load(handle)
except (OSError, ValueError):
    config = {}

config.setdefault("version", 1)
hooks = config.setdefault("hooks", {})

# Only the events that become a row. beforeShellExecution, afterShellExecution
# and postToolUse were captured too and say nothing preToolUse has not already
# said — registering them would double every line for a single command.
added, moved = [], []
for event in ["sessionStart", "beforeSubmitPrompt", "preToolUse", "stop", "sessionEnd"]:
    entries = hooks.setdefault(event, [])
    # Repoint an older install rather than adding beside it — Cursor keeps the
    # command on the entry itself rather than nested as Claude does.
    existing = [e for e in entries
                if isinstance(e, dict) and "cc-notify" in (e.get("command") or "")]
    if existing:
        for entry in existing:
            if entry["command"] != command:
                entry["command"] = command
                if event not in moved:
                    moved.append(event)
        continue
    entries.append({"command": command})
    added.append(event)

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
if added or moved:
    print("Registered Cursor's own agent in ~/.cursor/hooks.json")
    print("  Restart Cursor — it reads hooks.json at startup.")
else:
    print("Cursor's own agent was already registered (no change, no restart).")
CURSOR
fi

# Only after both configs have been repointed: a half-migrated setup that has
# lost its emitter is worse than one that still has the old file lying about.
if [ -f "$LEGACY" ]; then
  rm -f "$LEGACY"
  echo "Removed the previous copy at $LEGACY"
  rmdir "${HOME}/bin" 2>/dev/null || true
fi
if [ -d "$LEGACY_SUPPORT" ]; then
  rm -rf "$LEGACY_SUPPORT"
  echo "Removed the previous copy at $LEGACY_SUPPORT"
fi

echo
echo "Done. Hooks take effect immediately — no restart needed."
echo "Verify with a fresh session, then: ls \"\${TMPDIR:-/tmp}/groundcontrol/\""
