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

BIN_DIR="${HOME}/bin"
SETTINGS="${HOME}/.claude/settings.json"
SRC="$(cd "$(dirname "$0")" && pwd)/cc-notify"

install -d "$BIN_DIR"
install -m 0755 "$SRC" "$BIN_DIR/cc-notify"
echo "Installed cc-notify -> $BIN_DIR/cc-notify"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "NOTE: $BIN_DIR is not on your PATH (the hook uses an absolute path, so this is cosmetic)." ;;
esac

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

BACKUP="${SETTINGS}.bak-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"
echo "Backed up settings -> $BACKUP"

/usr/bin/python3 - "$SETTINGS" "$BIN_DIR/cc-notify" <<'PY'
import json, sys

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
added = []

for event in events:
    entries = hooks.setdefault(event, [])
    already = any(
        command in (hook.get("command") or "")
        for entry in entries if isinstance(entry, dict)
        for hook in entry.get("hooks", []) if isinstance(hook, dict)
    )
    if already:
        continue
    entries.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": command}],
    })
    added.append(event)

with open(settings_path, "w") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")

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
added = []
for event in ["sessionStart", "beforeSubmitPrompt", "preToolUse", "stop", "sessionEnd"]:
    entries = hooks.setdefault(event, [])
    if any(command in (e.get("command") or "") for e in entries if isinstance(e, dict)):
        continue
    entries.append({"command": command})
    added.append(event)

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
if added:
    print("Registered Cursor's own agent in ~/.cursor/hooks.json")
    print("  Restart Cursor — it reads hooks.json at startup.")
else:
    print("Cursor's own agent was already registered (no change, no restart).")
CURSOR
fi

echo
echo "Done. Hooks take effect immediately — no restart needed."
echo "Verify with a fresh session, then: ls \"\${TMPDIR:-/tmp}/groundcontrol/\""
