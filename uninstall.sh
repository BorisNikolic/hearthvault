#!/bin/bash
# HearthVault uninstaller.
# Removes the mechanism: hooks, the /vault-cleanup command, the settings.json
# registration, the launchd schedule, the config, and the cached clone.
# YOUR VAULT (the markdown notes and their git history) IS NEVER TOUCHED —
# delete that folder yourself if you really want it gone.
# Run: curl -fsSL https://raw.githubusercontent.com/BorisNikolic/hearthvault/main/uninstall.sh | bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hearthvault"
CLAUDE_DIR="$HOME/.claude"
VAULT="(unknown)"
[ -f "$CONFIG_DIR/config" ] && . "$CONFIG_DIR/config"

# 1. launchd schedule (macOS)
if [ "$(uname)" = "Darwin" ]; then
  launchctl bootout "gui/$(id -u)/com.hearthvault.janitor" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/com.hearthvault.janitor.plist"
  echo "removed janitor schedule"
fi

# 2. Hooks + command
rm -f "$CLAUDE_DIR/hooks/vault-context.sh" "$CLAUDE_DIR/hooks/vault-autocommit.sh" \
      "$CLAUDE_DIR/hooks/vault-stale-check.sh" "$CLAUDE_DIR/commands/vault-cleanup.md"
echo "removed hooks and /vault-cleanup command"

# 3. Deregister from settings.json (keep everything that isn't ours)
SETTINGS="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS" ] && command -v jq >/dev/null; then
  cp "$SETTINGS" "$SETTINGS.bak"
  jq '
    def prune: map(select([.hooks[]?.command // empty] | any(contains("vault-context.sh") or contains("vault-stale-check.sh") or contains("vault-autocommit.sh")) | not));
    if .hooks then
      .hooks.SessionStart = ((.hooks.SessionStart // []) | prune) |
      .hooks.Stop         = ((.hooks.Stop         // []) | prune) |
      .hooks.PostToolUse  = ((.hooks.PostToolUse  // []) | prune) |
      .hooks = (.hooks | with_entries(select(.value != [])))
    else . end
  ' "$SETTINGS.bak" > "$SETTINGS"
  echo "deregistered hooks from $SETTINGS (backup at settings.json.bak)"
fi

# 4. Config + cached clone
rm -rf "$CONFIG_DIR" "$HOME/.hearthvault"
echo "removed config and cached clone"

echo
echo "HearthVault removed. Your vault at $VAULT was NOT touched — your notes"
echo "and their full git history are still there. Delete that folder manually"
echo "if you truly want the data gone."
