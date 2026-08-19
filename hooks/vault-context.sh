#!/bin/bash
# HearthVault — SessionStart hook.
# Injects the hot tier into work sessions: Now.md (the index) plus only the
# Now/*.md caches touched in the last FRESH_DAYS days. Older caches stay on
# disk, indexed in Now.md, one Read away. Also flags unprocessed Inbox files
# when the session starts inside the vault.
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/hearthvault/config"
[ -f "$CONFIG" ] && . "$CONFIG"
VAULT="${VAULT:-$HOME/Brain}"
WORK_DIRS="${WORK_DIRS:-}"   # colon-separated extra dirs that should receive the vault context
FRESH_DAYS="${FRESH_DAYS:-14}"

INPUT=$(cat)

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

CONTEXT="=== Work vault hot cache: $VAULT/Now.md ===
$(cat "$VAULT/Now.md")"

# Per-ticket / per-workstream caches — only those touched recently.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  CONTEXT="$CONTEXT

=== Hot cache: Now/$(basename "$f") ===
$(cat "$f")"
done < <(find "$VAULT/Now" -maxdepth 1 -type f -name '*.md' -mtime -"$FRESH_DAYS" 2>/dev/null | sort)

SKIPPED=$(find "$VAULT/Now" -maxdepth 1 -type f -name '*.md' ! -mtime -"$FRESH_DAYS" 2>/dev/null | sort | xargs -I{} basename {} .md | tr '\n' ' ')
[ -n "$SKIPPED" ] && CONTEXT="$CONTEXT

(Not injected — Now/ caches idle >${FRESH_DAYS} days, Read on demand: $SKIPPED)"

case "$PWD" in
  "$VAULT"*)
    INBOX=$(find "$VAULT/Inbox" -maxdepth 1 -type f ! -name '.*' 2>/dev/null)
    if [ -n "$INBOX" ]; then
      CONTEXT="$CONTEXT

INBOX_PENDING: unprocessed files in Inbox/ — process them per the vault CLAUDE.md (extract decisions/facts into the right notes, move raw file to Inbox/Processed/, refresh the relevant Now/ cache):
$INBOX"
    fi
    ;;
esac

jq -n --arg ctx "$CONTEXT" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
