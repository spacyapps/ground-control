#!/bin/bash
# install-hooks.sh — install cc-notify and register it in Claude Code settings.
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
events = ["UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SubagentStop"]
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

echo
echo "Done. Hooks take effect immediately — no restart needed."
echo "Verify with a fresh session, then: ls \"\${TMPDIR:-/tmp}/skinterminal/\""
