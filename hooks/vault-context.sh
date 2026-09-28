#!/bin/bash
# HearthVault — SessionStart hook.
# Injects the hot tier into work sessions and flags unprocessed Inbox files when the
# session starts inside the vault.
# Hook output over 10,000 characters reaches the agent only as a 2,000-character preview,
# so the output is built in priority order under BUDGET: the current branch's topic
# cache, then Now.md's index sections, with pointers to everything that did not fit.
# Now.md is read by heading: `**Last updated:**`, `## Active workstreams`, `## Cross-cutting`.
# Topic caches named after a ticket ID (Now/PROJ-123.md) are matched to a branch that
# contains it (feature/PROJ-123-short-name).
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/hearthvault/config"
[ -f "$CONFIG" ] && . "$CONFIG"
VAULT="${VAULT:-$HOME/Brain}"
WORK_DIRS="${WORK_DIRS:-}"   # colon-separated extra dirs that should receive the vault context
export LC_ALL=en_US.UTF-8
BUDGET=9700
RESERVE=500
LIST_MAX=15
INPUT=$(cat)

in_scope=0
case "$PWD" in "$VAULT"|"$VAULT"/*) in_scope=1 ;; esac
OLD_IFS=$IFS; IFS=':'
for d in $WORK_DIRS; do
  [ -n "$d" ] || continue
  case "$PWD" in "$d"|"$d"/*) in_scope=1 ;; esac
done
IFS=$OLD_IFS
[ "$in_scope" = 1 ] || exit 0
[ -f "$VAULT/Now.md" ] || exit 0

# Claude Code measures the cap in UTF-16 units, ${#} counts code points, so every
# 4-byte UTF-8 character (emoji) costs one extra unit.
u16len() {
  local astral
  astral=$(printf '%s' "$1" | LC_ALL=C tr -cd '\360-\364' | wc -c)
  echo $(( ${#1} + astral ))
}

# Prefix of $1 that fits in $2 UTF-16 units. Dropping k characters frees k to 2k units,
# so dropping half the excess each round at least halves it.
fit() {
  local cut="${1:0:$2}" over
  over=$(( $(u16len "$cut") - $2 ))
  while [ $over -gt 0 ]; do
    cut="${cut:0:$(( ${#cut} - (over + 1) / 2 ))}"
    over=$(( $(u16len "$cut") - $2 ))
  done
  printf '%s' "$cut"
}

# Prints the first LIST_MAX lines of stdin, then how many were left out and where.
capped() {
  awk -v max="$LIST_MAX" -v where="$1" \
    'NR <= max { print } END { if (NR > max) printf "- ... and %d more: %s\n", NR - max, where }'
}

# Ticket from the branch name, e.g. feature/PROJ-123-short-name -> PROJ-123.
# HEAD is detached during a rebase, so fall back to the branch being rebased.
BRANCH=$(git -C "$PWD" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
if [ -z "$BRANCH" ]; then
  for d in rebase-merge rebase-apply; do
    p=$(git -C "$PWD" rev-parse --path-format=absolute --git-path "$d/head-name" 2>/dev/null)
    [ -f "$p" ] && BRANCH=$(sed 's#^refs/heads/##' "$p") && break
  done
fi
TICKET=$(printf '%s' "$BRANCH" | grep -oE '[A-Z]+-[0-9]+' | head -1)
TICKET_FILE=""
if [ -n "$TICKET" ]; then
  for f in "$VAULT/Now/$TICKET.md" "$VAULT/Now/Done/$TICKET.md"; do
    [ -f "$f" ] && TICKET_FILE="$f" && break
  done
fi

# The footer is always emitted in full, so its size is reserved before the body is filled.
FOOTER="

=== Other hot-cache files (Read on demand) ===
- $VAULT/Now.md: full index, incl. $(grep '^## ' "$VAULT/Now.md" | sed 's/^## //; s/ (.*//; s/ —.*//' | paste -sd ',' - | sed 's/,/, /g')
$(find "$VAULT/Now" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort | while IFS= read -r f; do
  [ "$f" = "$TICKET_FILE" ] || echo "- $f (updated $(stat -f '%Sm' -t '%Y-%m-%d' "$f"))"
done | capped "ls $VAULT/Now")"

case "$PWD" in
  "$VAULT"|"$VAULT"/*)
    INBOX=$(find "$VAULT/Inbox" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | sort)
    if [ -n "$INBOX" ]; then
      FOOTER="$FOOTER

INBOX_PENDING: unprocessed files in Inbox/ — process them per the vault CLAUDE.md (extract decisions/facts into the right notes, move raw file to Inbox/Processed/, refresh the relevant Now/ cache):
$(printf '%s\n' "$INBOX" | capped "ls $VAULT/Inbox")"
    fi
    ;;
esac

CONTEXT=""
OMITTED=""
ROOM=$(( BUDGET - $(u16len "$FOOTER") - RESERVE ))

# Appends text $3 whole if it fits, otherwise as much as fits plus a pointer to file $2.
# Returns 1 and records label $1 when not even a useful part fits.
add() {
  local left=$(( ROOM - $(u16len "$CONTEXT") ))
  if [ "$(u16len "$3")" -le $left ]; then
    CONTEXT="$CONTEXT$3"
    return 0
  fi
  local note="
[... cut to fit the hook limit. Read $2 for the rest.]"
  left=$(( left - $(u16len "$note") ))
  if [ $left -gt 300 ]; then
    CONTEXT="$CONTEXT$(fit "$3" $left)$note"
    return 0
  fi
  OMITTED="$OMITTED${OMITTED:+, }$1 (no room, see $2)"
  return 1
}

# Adds one part of Now.md; $2 is its text, empty when the heading was not found.
add_now() {
  if [ -z "$2" ]; then
    OMITTED="$OMITTED${OMITTED:+, }$1 (heading not found in $VAULT/Now.md)"
    return
  fi
  add "$1" "$VAULT/Now.md" "

$2"
}

section() {
  awk -v h="$1" 'index($0, h) == 1 { on = 1; print; next } on && /^## / { exit } on { print }' "$VAULT/Now.md"
}

add "Intro" "$VAULT/Now.md" "=== Vault hot cache ($VAULT), trimmed to fit the hook output limit ===
This is a starting point, not the whole state. When the task touches a workstream below, Read its full file. Before writing to the vault, Read $VAULT/CLAUDE.md."

TICKET_INJECTED=""
[ -n "$TICKET_FILE" ] && add "Current topic cache" "$TICKET_FILE" "

=== Current branch $BRANCH → $TICKET_FILE ===
$(cat "$TICKET_FILE")" && TICKET_INJECTED=1

add "Now.md header" "$VAULT/Now.md" "

=== $VAULT/Now.md (index sections) ==="
add_now "Last updated" "$(grep -m1 '^\*\*Last updated:\*\*' "$VAULT/Now.md")"
add_now "Active workstreams" "$(section '## Active workstreams')"
add_now "Cross-cutting" "$(section '## Cross-cutting')"

CONTEXT="$CONTEXT$FOOTER"
[ -n "$TICKET_FILE" ] && [ -z "$TICKET_INJECTED" ] && CONTEXT="$CONTEXT
- $TICKET_FILE (current branch $BRANCH, not injected: Read it first)"
[ -n "$OMITTED" ] && CONTEXT="$CONTEXT
Not injected: $OMITTED. Read it before relying on it."

# Backstop: never let the output reach the cap, whatever the content.
[ "$(u16len "$CONTEXT")" -gt 9900 ] && CONTEXT="$(fit "$CONTEXT" 9800)"

jq -n --arg ctx "$CONTEXT" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
exit 0
