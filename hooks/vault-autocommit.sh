#!/bin/bash
# HearthVault — PostToolUse(Write|Edit) hook.
# Auto-commits any pending change in the vault. Git is the undo: the agent
# writes freely, every state is recoverable.
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/hearthvault/config"
[ -f "$CONFIG" ] && . "$CONFIG"
VAULT="${VAULT:-$HOME/Brain}"

[ -d "$VAULT/.git" ] || exit 0
cd "$VAULT" || exit 0
git add -A >/dev/null 2>&1
git diff --cached --quiet 2>/dev/null && exit 0
git commit -q -m "vault: auto-commit $(date '+%Y-%m-%d %H:%M')" >/dev/null 2>&1
exit 0
