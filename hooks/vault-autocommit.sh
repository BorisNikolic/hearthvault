#!/bin/bash
# HearthVault — PostToolUse(Write|Edit|Bash) hook.
# Auto-commits any pending change in the vault. Git is the undo: the agent writes
# freely, every state is recoverable.
# Several Claude profiles (CLAUDE_CONFIG_DIR), the janitor and your editor can change the
# vault at the same time, so commits run one at a time under lockf (macOS has no flock).
# A Write or Edit to a vault file is queued before waiting for the lock, so whoever holds
# the lock first gives it its own commit, labelled with its profile. Everything else
# pending is swept after. Problems go to .git/claude-autocommit.log instead of being
# swallowed. Always exits 0.
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/hearthvault/config"
[ -f "$CONFIG" ] && . "$CONFIG"
VAULT="${VAULT:-$HOME/Brain}"
[ -d "$VAULT/.git" ] || exit 0
LOG="$VAULT/.git/claude-autocommit.log"
QUEUE="$VAULT/.git/claude-autocommit.queue"

# Appends a dated line. The same message within an hour is skipped, so a stuck state
# does not grow the log on every tool call.
log() {
  local msg="[$PROFILE] $*" last then_s
  last=$(tail -n 1 "$LOG" 2>/dev/null)
  if [ "${last#* * }" = "$msg" ]; then
    then_s=$(date -j -f '%Y-%m-%d %H:%M:%S' "${last%% \[*}" +%s 2>/dev/null || echo 0)
    [ $(( $(date +%s) - then_s )) -lt 3600 ] && return
  fi
  if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 262144 ]; then
    tail -n 1000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOG"
}

if [ "$1" != "--locked" ]; then
  INPUT=$(cat)
  # Profile label: the config dir's name without its dot, "default" when unset.
  PROFILE=$(basename "${CLAUDE_CONFIG_DIR:-default}")
  PROFILE="${PROFILE#.}"
  case "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')" in
    Write|Edit)
      FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
      case "$FILE" in
        "$VAULT"/*) printf '%s\t%s\n' "$PROFILE" "${FILE#"$VAULT"/}" >> "$QUEUE" ;;
      esac
      ;;
  esac
  # Cheap exit without the lock when nothing is pending. A failing status is not "clean".
  if st=$(git -C "$VAULT" --no-optional-locks status --porcelain --untracked-files=normal 2>/dev/null); then
    [ -z "$st" ] && [ ! -s "$QUEUE" ] && exit 0
  fi
  if [ -x /usr/bin/lockf ]; then
    /usr/bin/lockf -k -t 60 "$VAULT/.git/claude-autocommit.lock" /bin/bash "$0" --locked "$PROFILE" 2> /dev/null
    rc=$?
    [ $rc -eq 0 ] || log "lockf exited $rc (75: lock busy for 60s), left for the next call"
  else
    /bin/bash "$0" --locked "$PROFILE" 2> /dev/null
  fi
  exit 0
fi

PROFILE="$2"
cd "$VAULT" || exit 0
export GIT_LITERAL_PATHSPECS=1
STAMP=$(date '+%Y-%m-%d %H:%M')

# A merge, rebase or detached HEAD needs a human. The changes stay in the tree until then.
if [ -e .git/MERGE_HEAD ] || [ -e .git/CHERRY_PICK_HEAD ] || [ -d .git/rebase-merge ] ||
  [ -d .git/rebase-apply ] || ! git symbolic-ref -q HEAD > /dev/null; then
  log "merge, rebase or detached HEAD in progress, not committing"
  exit 0
fi

# Retries only while another git process holds .git/index.lock. Any other error is
# logged at once and not retried.
try() {
  local attempt err
  for attempt in 1 2 3 4 5; do
    err=$("$@" 2>&1) && return 0
    case "$err" in
      *index.lock*) sleep 1 ;;
      *) break ;;
    esac
  done
  log "failed: $* :: $(printf '%s' "$err" | head -n 1)"
  return 1
}

if [ -s "$QUEUE" ]; then
  mv "$QUEUE" "$QUEUE.work"
  awk -F'\t' '!seen[$2]++' "$QUEUE.work" | while IFS=$'\t' read -r who file; do
    [ -n "$file" ] && [ -e "$file" ] || continue
    # check-ignore takes plain paths and rejects GIT_LITERAL_PATHSPECS.
    env -u GIT_LITERAL_PATHSPECS git check-ignore -q -- "$file" 2> /dev/null && continue
    try git add -- "$file" || continue
    git diff --cached --quiet -- "$file" || try git commit -q -m "vault: auto-commit $STAMP ($who): $file" -- "$file"
  done
  rm -f "$QUEUE.work"
fi

try git add -A || exit 0
if ! git diff --cached --quiet; then
  FILES=$(git diff --cached --name-only)
  COUNT=$(printf '%s\n' "$FILES" | wc -l | tr -d ' ')
  NAMES=$(printf '%s\n' "$FILES" | head -n 3 | paste -sd ',' - | sed 's/,/, /g')
  [ "$COUNT" -gt 3 ] && NAMES="$NAMES +$(( COUNT - 3 )) more"
  try git commit -q -m "vault: auto-commit $STAMP (sweep by $PROFILE): $NAMES"
fi
exit 0
