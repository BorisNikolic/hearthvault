#!/bin/bash
# HearthVault — Stop hook.
# If a vault note changed more recently than the freshest hot-cache file
# (Now.md or any Now/*.md), nudge the agent to refresh the relevant cache
# before the turn ends. This is what keeps the hot tier trustworthy.
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/hearthvault/config"
[ -f "$CONFIG" ] && . "$CONFIG"
VAULT="${VAULT:-$HOME/Brain}"
WORK_DIRS="${WORK_DIRS:-}"

INPUT=$(cat)
# Don't re-nudge if this turn is already a stop-hook continuation
printf '%s' "$INPUT" | grep -q '"stop_hook_active":[[:space:]]*true' && exit 0

in_scope=0
case "$PWD" in "$VAULT"*) in_scope=1 ;; esac
OLD_IFS=$IFS; IFS=':'
for d in $WORK_DIRS; do
  [ -n "$d" ] || continue
  case "$PWD" in "$d"*) in_scope=1 ;; esac
done
IFS=$OLD_IFS
[ "$in_scope" = 1 ] || exit 0
[ -f "$VAULT/Now.md" ] || exit 0

# Newest hot-cache file (Now.md + Now/*.md) by mtime
NEWEST=$(ls -t "$VAULT/Now.md" "$VAULT"/Now/*.md 2>/dev/null | head -1)
[ -n "$NEWEST" ] || exit 0

# Any content note newer than that (excludes the caches themselves, CLAUDE.md, dotfiles)
STALE=$(find "$VAULT" -name '*.md' \
  ! -path "$VAULT/Now.md" ! -path "$VAULT/Now/*" \
  ! -name 'CLAUDE.md' ! -path '*/.*' \
  -newer "$NEWEST" -print -quit 2>/dev/null)

if [ -n "$STALE" ]; then
  jq -n --arg msg "VAULT_HOT_CACHE_STALE: a vault note changed since the hot cache was last refreshed (e.g. $STALE). If it relates to what you worked on this turn, refresh the matching $VAULT/Now/<topic>.md (or Now.md for cross-cutting) and bump its timestamp, then stop. If nothing cache-worthy changed this turn, just stop." \
    '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $msg}}'
fi
exit 0
