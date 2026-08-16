#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
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

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

BACKUP="${SETTINGS}.bak-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"
echo "Backed up settings -> $BACKUP"

# Keep the three most recent. A backup per run is right; thirty-five of them,
# which is what developing this produced, is a mess in someone else's folder.
prune() {
  ls -t "$1".bak-* 2>/dev/null | tail -n +4 | while read -r old; do rm -f "$old"; done
}
prune "$SETTINGS"

/usr/bin/python3 - "$SETTINGS" "$BIN_DIR/cc-notify" <<'PY'
import json, os, sys

settings_path, command = sys.argv[1], sys.argv[2]

with open(settings_path) as handle:
    settings = json.load(handle)

hooks = settings.setdefault("hooks", {})
# SessionStart/SessionEnd/SubagentStart are Grok's; harmless where unsupported,
# and SessionEnd is what lets a row vanish on quit instead of ageing out.
events = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "Notification",
    "Stop", "SubagentStart", "SubagentStop", "SessionEnd",
]
added, moved, retired = [], [], set()


def ours(hook):
    return isinstance(hook, dict) and "cc-notify" in (hook.get("command") or "")


for event in events:
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
        "matcher": "",
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

# --- Cursor's own agent -------------------------------------------------
#
# Composer is not a terminal process, so nothing above reaches it: Cursor reads
# its own ~/.cursor/hooks.json and nothing from ~/.claude. Its payloads are
# snake_case like Claude's, and three of its event names already normalise to
# ours, so cc-notify needs no separate emitter — only registering.
#
# Skipped silently where Cursor is not installed. Claude Code running *inside*
# Cursor's terminal is covered by the block above and needs none of this.
if [ -d "$HOME/.cursor" ]; then
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
