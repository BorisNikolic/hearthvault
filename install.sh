#!/bin/bash
# HearthVault installer.
# Sets up the vault, hooks, janitor command, config, and (optionally) the
# weekly launchd schedule. Safe to re-run; existing files are backed up.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
VAULT="${1:-$HOME/Brain}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hearthvault"
CLAUDE_DIR="$HOME/.claude"

echo "HearthVault install"
echo "  vault:  $VAULT"
echo "  config: $CONFIG_DIR/config"
echo

command -v jq >/dev/null || { echo "ERROR: jq is required (brew install jq)"; exit 1; }
command -v git >/dev/null || { echo "ERROR: git is required"; exit 1; }

# 1. Config
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config" ]; then
  cat > "$CONFIG_DIR/config" <<EOF
# HearthVault configuration (sourced by the hooks)
VAULT="$VAULT"
# Colon-separated extra directories whose sessions should receive vault context:
WORK_DIRS="\$HOME/WORK"
# How many days a Now/ cache stays "hot" (injected at session start):
FRESH_DAYS=14
EOF
  echo "wrote $CONFIG_DIR/config"
else
  echo "kept existing $CONFIG_DIR/config (edit VAULT there if needed)"
fi

# 2. Vault skeleton
if [ ! -d "$VAULT" ]; then
  cp -R "$REPO_DIR/vault-template" "$VAULT"
  ( cd "$VAULT" && git init -q && git add -A && git commit -qm "vault: initial skeleton" )
  echo "created vault at $VAULT (git initialized)"
else
  echo "kept existing vault at $VAULT"
fi

# 3. Hooks + janitor command
mkdir -p "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/logs"
for f in vault-context.sh vault-autocommit.sh vault-stale-check.sh; do
  [ -f "$CLAUDE_DIR/hooks/$f" ] && cp "$CLAUDE_DIR/hooks/$f" "$CLAUDE_DIR/hooks/$f.bak"
  cp "$REPO_DIR/hooks/$f" "$CLAUDE_DIR/hooks/$f"
  chmod +x "$CLAUDE_DIR/hooks/$f"
done
[ -f "$CLAUDE_DIR/commands/vault-cleanup.md" ] && cp "$CLAUDE_DIR/commands/vault-cleanup.md" "$CLAUDE_DIR/commands/vault-cleanup.md.bak"
cp "$REPO_DIR/commands/vault-cleanup.md" "$CLAUDE_DIR/commands/vault-cleanup.md"
echo "installed hooks and /vault-cleanup command into $CLAUDE_DIR"

# 4. Hook registration — print the snippet, don't silently edit settings.json
cat <<'EOF'

Add this to the "hooks" section of ~/.claude/settings.json (merge with what's there):

  "SessionStart": [
    { "matcher": "startup|resume|clear|compact",
      "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/vault-context.sh", "statusMessage": "Loading work vault hot cache" } ] }
  ],
  "Stop": [
    { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/vault-stale-check.sh" } ] }
  ],
  "PostToolUse": [
    { "matcher": "Write|Edit",
      "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/vault-autocommit.sh", "async": true } ] }
  ]
EOF

# 5. Optional launchd schedule (macOS)
if [ "$(uname)" = "Darwin" ]; then
  printf "\nInstall the weekly janitor (launchd, Mondays 08:07)? [y/N] "
  read -r yn
  if [ "${yn:-n}" = "y" ] || [ "${yn:-n}" = "Y" ]; then
    PLIST="$HOME/Library/LaunchAgents/com.hearthvault.janitor.plist"
    sed -e "s|__VAULT__|$VAULT|g" -e "s|__HOME__|$HOME|g" \
      "$REPO_DIR/launchd/com.hearthvault.janitor.plist" > "$PLIST"
    launchctl bootout "gui/$(id -u)/com.hearthvault.janitor" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "janitor scheduled: Mondays 08:07, log in ~/.claude/logs/hearthvault-janitor.log"
  else
    echo "skipped; you can always run /vault-cleanup manually"
  fi
fi

echo
echo "Done. Rename $VAULT/Client/ to your project's name, open the vault in Obsidian if you use it,"
echo "and start a Claude Code session inside the vault or a configured work dir."
