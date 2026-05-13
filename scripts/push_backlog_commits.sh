#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  push_backlog_commits.sh [options]

Create one commit per day over a date range by appending log lines to a file,
then push to a branch.

Options:
  --start YYYY-MM-DD       Start date (default: 1 year before --end)
  --end YYYY-MM-DD         End date (default: today, UTC)
  --branch NAME            Branch to commit/push to (default: backlog-activity)
  --file PATH              File to write activity logs (default: backlog-activity.log)
  --remote NAME            Remote name (default: origin)
  --message-prefix TEXT    Commit message prefix (default: chore: backlog activity)
  --dry-run                Print what would happen without committing/pushing
  -h, --help               Show help

Examples:
  ./scripts/push_backlog_commits.sh --dry-run
  ./scripts/push_backlog_commits.sh --start 2025-01-01 --end 2025-12-31
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: missing required command '$1'" >&2
    exit 1
  }
}

START_DATE=""
END_DATE="$(date -u +%F)"
BRANCH="backlog-activity"
LOG_FILE="backlog-activity.log"
REMOTE="origin"
MESSAGE_PREFIX="chore: backlog activity"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start) START_DATE="${2:-}"; shift 2 ;;
    --end) END_DATE="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --file) LOG_FILE="${2:-}"; shift 2 ;;
    --remote) REMOTE="${2:-}"; shift 2 ;;
    --message-prefix) MESSAGE_PREFIX="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

require_cmd git
require_cmd date

if [[ -z "$START_DATE" ]]; then
  START_DATE="$(date -u -d "$END_DATE -1 year +1 day" +%F)"
fi

if ! date -u -d "$START_DATE" +%F >/dev/null 2>&1; then
  echo "Error: invalid --start date '$START_DATE'" >&2
  exit 1
fi

if ! date -u -d "$END_DATE" +%F >/dev/null 2>&1; then
  echo "Error: invalid --end date '$END_DATE'" >&2
  exit 1
fi

start_epoch="$(date -u -d "$START_DATE" +%s)"
end_epoch="$(date -u -d "$END_DATE" +%s)"

if (( start_epoch > end_epoch )); then
  echo "Error: --start must be on or before --end" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: run this script from inside a git repository." >&2
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"

run() {
  if $DRY_RUN; then
    printf '[dry-run] %s\n' "$*"
  else
    eval "$@"
  fi
}

run "git checkout -B '$BRANCH'"

day_epoch="$start_epoch"
commit_count=0

while (( day_epoch <= end_epoch )); do
  day="$(date -u -d "@$day_epoch" +%F)"
  timestamp="${day}T12:00:00"
  line="${day} | backlog activity logged"

  run "printf '%s\n' '$line' >> '$LOG_FILE'"
  run "git add '$LOG_FILE'"

  if $DRY_RUN; then
    printf '[dry-run] commit on %s\n' "$timestamp"
  else
    GIT_AUTHOR_DATE="$timestamp" GIT_COMMITTER_DATE="$timestamp" \
      git commit -m "${MESSAGE_PREFIX} ${day}" >/dev/null
  fi

  commit_count=$((commit_count + 1))
  day_epoch=$((day_epoch + 86400))
done

run "git push -u '$REMOTE' '$BRANCH'"

printf 'Done. Created %d commits from %s through %s on branch %s (started from %s).\n' \
  "$commit_count" "$START_DATE" "$END_DATE" "$BRANCH" "$current_branch"
