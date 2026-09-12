#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Walter Mak
# uninstall-hooks.sh — unregister cc-notify and remove it.
#
# Run this *before* dragging the app to the Trash, or don't — a copy of this
# script is installed alongside the emitter precisely so the order cannot
# matter. Deleting the app first would otherwise leave every agent CLI calling
# a command that no longer exists, on every tool use.
#
# Removes only what we registered. Hooks belonging to anything else are left
# exactly as they are, in both config files.
#
# Your themes are *not* touched: they live beside this folder and are yours.
set -euo pipefail

SUPPORT="${HOME}/Library/Application Support/GroundControl"
BIN_DIR="${HOME}/.groundcontrol"
LEGACY="${HOME}/bin/cc-notify"
LEGACY_SUPPORT="${SUPPORT}/bin"

unregister() {
  local path="$1" label="$2"
  [ -f "$path" ] || return 0

  # Nothing of ours in there means nothing to undo. Backing up regardless left
  # ten copies of an empty file in ~/.cursor after a few flicks of the switch —
  # a backup of a file we are not about to change is just litter in somebody
  # else's folder.
  if ! grep -q "cc-notify" "$path"; then
    echo "  $label: nothing of ours registered"
    return 0
  fi

  cp "$path" "${path}.bak-$(date +%Y%m%d-%H%M%S)"
  # Keep the three most recent, as the installer does.
  ls -t "$path".bak-* 2>/dev/null | tail -n +4 | while read -r old; do rm -f "$old"; done
  /usr/bin/python3 - "$path" "$label" <<'PY'
import json, sys

path, label = sys.argv[1], sys.argv[2]
try:
    with open(path) as handle:
        config = json.load(handle)
except (OSError, ValueError):
    raise SystemExit

hooks = config.get("hooks")
if not isinstance(hooks, dict):
    raise SystemExit

# Ours is any command naming cc-notify, wherever it was installed — the old
# ~/bin location included, so an upgrade that moved it still cleans up.
def ours(command):
    return "cc-notify" in (command or "")

removed = 0
for event, entries in list(hooks.items()):
    if not isinstance(entries, list):
        continue
    kept = []
    for entry in entries:
        if not isinstance(entry, dict):
            kept.append(entry)
            continue
        # Claude nests commands one level deeper than Cursor does.
        inner = entry.get("hooks")
        if isinstance(inner, list):
            survivors = [h for h in inner if not ours(h.get("command"))]
            removed += len(inner) - len(survivors)
            if survivors:
                entry["hooks"] = survivors
                kept.append(entry)
            continue
        if ours(entry.get("command")):
            removed += 1
            continue
        kept.append(entry)
    if kept:
        hooks[event] = kept
    else:
        del hooks[event]

with open(path, "w") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
print("  %s: removed %d registration(s)" % (label, removed))
PY
}

# One agent at a time, or everything. Settings offers a switch per integration,
# and turning Cursor off must not take Claude Code's emitter with it.
TARGET="${1:-all}"

# opencode is a plugin rather than a command, so removing it means taking the
# file away and taking our line out of its config — leaving either behind would
# have opencode loading a plugin that is not there.
unregister_opencode() {
  local dir="${HOME}/.config/opencode"
  [ -d "$dir" ] || return 0
  rm -f "$dir/plugin/groundcontrol.ts"

  local config="$dir/opencode.json"
  [ -f "$config" ] || { [ -f "$dir/opencode.jsonc" ] && config="$dir/opencode.jsonc"; }
  [ -f "$config" ] || return 0
  grep -q "groundcontrol" "$config" || { echo "  opencode: nothing of ours registered"; return 0; }

  cp "$config" "${config}.bak-$(date +%Y%m%d-%H%M%S)"
  ls -t "$config".bak-* 2>/dev/null | tail -n +4 | while read -r old; do rm -f "$old"; done
  /usr/bin/python3 - "$config" <<'OPENCODE'
import json, sys
path = sys.argv[1]
try:
    with open(path) as handle:
        config = json.load(handle)
except Exception:
    print("  could not parse %s — remove the groundcontrol plugin line yourself" % path)
    raise SystemExit(0)
plugins = config.get("plugin")
if isinstance(plugins, list):
    kept = [p for p in plugins if not (isinstance(p, str) and "groundcontrol" in p)]
    if kept:
        config["plugin"] = kept
    else:
        config.pop("plugin", None)
    with open(path, "w") as handle:
        json.dump(config, handle, indent=2)
        handle.write("\n")
print("  opencode: removed the plugin")
OPENCODE
}

# Codex's registration is TOML in a file people also keep their model choice
# and per-project trust in, so only the sentinel block is taken out. The
# [hooks.state] trust record Codex wrote for itself is left alone deliberately:
# it names a hash of what was registered, becomes inert the moment the block is
# gone, and re-installing later then needs no second trip through the prompt.
unregister_codex() {
  local config="${HOME}/.codex/config.toml"
  [ -f "$config" ] || { echo "  Codex: nothing to remove"; return 0; }
  grep -qF "# >>> ground-control >>>" "$config" || {
    echo "  Codex: nothing of ours registered"; return 0; }

  cp "$config" "${config}.bak-$(date +%Y%m%d-%H%M%S)"
  ls -t "$config".bak-* 2>/dev/null | tail -n +4 | while read -r old; do rm -f "$old"; done
  awk -v b="# >>> ground-control >>>" -v e="# <<< ground-control <<<" '
    $0 == b { skip = 1 } skip != 1 { print } $0 == e { skip = 0 }
  ' "$config" > "${config}.gc-tmp"
  mv "${config}.gc-tmp" "$config"
  echo "  Codex: removed our block from config.toml"
}

echo "==> Unregistering"
case "$TARGET" in
  claude|all) unregister "${HOME}/.claude/settings.json" "Claude Code / Grok" ;;
esac
case "$TARGET" in
  codex|all) unregister_codex ;;
esac
case "$TARGET" in
  cursor|all) unregister "${HOME}/.cursor/hooks.json" "Cursor" ;;
esac
case "$TARGET" in
  opencode|all) unregister_opencode ;;
esac

# The emitter is shared, so it only goes when everything does. Removing it while
# another agent is still registered would leave that registration pointing at a
# file that is not there — the failure looks like the app is broken.
if [ "$TARGET" = "all" ]; then
  echo "==> Removing the emitter"
  rm -rf "$BIN_DIR"
  [ -f "$LEGACY" ] && rm -f "$LEGACY" && echo "  also removed the old ${LEGACY}"
  [ -d "$LEGACY_SUPPORT" ] && rm -rf "$LEGACY_SUPPORT" && echo "  also removed ${LEGACY_SUPPORT}"
else
  echo "==> Leaving the emitter in place; other integrations may still use it"
fi

echo
echo "Done. Hooks stop at your next agent session — a CLI already running keeps"
echo "the ones it loaded at startup."
echo
echo "Your themes are untouched, in:"
echo "  ${SUPPORT}/Themes"
echo "Delete that folder too if you want them gone. Then quit Ground Control and"
echo "drag it to the Trash."
