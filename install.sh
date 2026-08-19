#!/bin/bash
# HearthVault installer.
# Run from a clone:            ./install.sh [vault-name-or-path]
# Or without cloning anything: curl -fsSL https://raw.githubusercontent.com/BorisNikolic/hearthvault/main/install.sh | bash
# Safe to re-run; existing files are backed up, an existing vault is never touched.
set -euo pipefail

REPO_URL="https://github.com/BorisNikolic/hearthvault.git"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hearthvault"
CLAUDE_DIR="$HOME/.claude"

command -v git >/dev/null || { echo "ERROR: git is required"; exit 1; }
command -v jq  >/dev/null || { echo "ERROR: jq is required (brew install jq)"; exit 1; }

# --- Self-bootstrap: when run via curl|bash there is no local clone yet -----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/hooks" ]; then
  REPO_DIR="$SCRIPT_DIR"
else
  REPO_DIR="$HOME/.hearthvault/src"
  if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull -q --ff-only || true
  else
    mkdir -p "$(dirname "$REPO_DIR")"
    echo "Cloning HearthVault into $REPO_DIR ..."
    git clone -q "$REPO_URL" "$REPO_DIR"
  fi
fi

# --- Pick the vault name/path (prompts work even under curl|bash) -----------
ask() { # ask <prompt> <default>
  local answer=""
  if [ -t 0 ]; then
    printf '%s [%s] ' "$1" "$2"; read -r answer
  elif [ -e /dev/tty ]; then
    printf '%s [%s] ' "$1" "$2" > /dev/tty; read -r answer < /dev/tty
  fi
  printf '%s' "${answer:-$2}"
}

VAULT_INPUT="${1:-$(ask "Vault name (folder in ~) or full path:" "Brain")}"
case "$VAULT_INPUT" in
  /*)  VAULT="$VAULT_INPUT" ;;
  ~*)  VAULT="${VAULT_INPUT/#\~/$HOME}" ;;
  *)   VAULT="$HOME/$VAULT_INPUT" ;;
esac

echo
echo "HearthVault install"
echo "  vault:  $VAULT"
echo "  config: $CONFIG_DIR/config"
echo

# --- 1. Config ---------------------------------------------------------------
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
  echo "kept existing $CONFIG_DIR/config (edit VAULT there if you're switching vaults)"
fi

# --- 2. Vault skeleton -------------------------------------------------------
if [ ! -d "$VAULT" ]; then
  cp -R "$REPO_DIR/vault-template" "$VAULT"
  ( cd "$VAULT" && git init -q && git add -A && git commit -qm "vault: initial skeleton" )
  echo "created vault at $VAULT (git initialized)"
else
  echo "kept existing vault at $VAULT (not touched)"
fi

# --- 3. Hooks + janitor command ----------------------------------------------
mkdir -p "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/logs"
for f in vault-context.sh vault-autocommit.sh vault-stale-check.sh; do
  [ -f "$CLAUDE_DIR/hooks/$f" ] && cp "$CLAUDE_DIR/hooks/$f" "$CLAUDE_DIR/hooks/$f.bak"
  cp "$REPO_DIR/hooks/$f" "$CLAUDE_DIR/hooks/$f"
  chmod +x "$CLAUDE_DIR/hooks/$f"
done
[ -f "$CLAUDE_DIR/commands/vault-cleanup.md" ] && cp "$CLAUDE_DIR/commands/vault-cleanup.md" "$CLAUDE_DIR/commands/vault-cleanup.md.bak"
cp "$REPO_DIR/commands/vault-cleanup.md" "$CLAUDE_DIR/commands/vault-cleanup.md"
echo "installed hooks + /vault-cleanup command into $CLAUDE_DIR"

# --- 4. Register hooks in ~/.claude/settings.json ------------------------------
SETTINGS="$CLAUDE_DIR/settings.json"
NEEDED=$(cat <<'EOF'
{
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
}
EOF
)
if [ ! -f "$SETTINGS" ]; then
  jq -n --argjson h "$NEEDED" '{hooks: $h}' > "$SETTINGS"
  echo "created $SETTINGS with the hook registration"
elif jq -e '.hooks.SessionStart[]?.hooks[]?.command | select(contains("vault-context.sh"))' "$SETTINGS" >/dev/null 2>&1; then
  echo "hooks already registered in $SETTINGS"
else
  cp "$SETTINGS" "$SETTINGS.bak"
  jq --argjson h "$NEEDED" '
    .hooks //= {} |
    .hooks.SessionStart = ((.hooks.SessionStart // []) + $h.SessionStart) |
    .hooks.Stop         = ((.hooks.Stop         // []) + $h.Stop) |
    .hooks.PostToolUse  = ((.hooks.PostToolUse  // []) + $h.PostToolUse)
  ' "$SETTINGS.bak" > "$SETTINGS"
  echo "registered hooks in $SETTINGS (backup at settings.json.bak)"
fi

# --- 5. Optional weekly janitor (macOS launchd) --------------------------------
if [ "$(uname)" = "Darwin" ]; then
  yn=$(ask "Schedule the weekly janitor (Mondays 08:07)? y/N:" "n")
  if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
    PLIST="$HOME/Library/LaunchAgents/com.hearthvault.janitor.plist"
    sed -e "s|__VAULT__|$VAULT|g" -e "s|__HOME__|$HOME|g" \
      "$REPO_DIR/launchd/com.hearthvault.janitor.plist" > "$PLIST"
    launchctl bootout "gui/$(id -u)/com.hearthvault.janitor" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "janitor scheduled; log: ~/.claude/logs/hearthvault-janitor.log"
  else
    echo "skipped; run /vault-cleanup manually anytime"
  fi
fi

echo
echo "Done. Next steps:"
echo "  1. Rename $VAULT/Client/ (folder + Client.md) to your project's name."
echo "  2. Start a Claude Code session inside $VAULT — the hot cache loads automatically."
