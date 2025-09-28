#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required}"
BACKLOG_GLOB=${BACKLOG_GLOB:-scripts/backlog/*.json}
LOG_DIR=${LOG_DIR:-/tmp}
LOG_FILE="$LOG_DIR/ae-backlog-sync.log"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EVENTS_FILE="$ROOT_DIR/telemetry/events.ndjson"
mkdir -p "$LOG_DIR" "$ROOT_DIR/telemetry"

for cmd in jq gh; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 2
  fi
done

emit_event(){
  local status="$1" msg="$2" ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  jq -nc --arg ts "$ts" --arg agent "backlog-sync" --arg role "backlog" --arg kind "backlog" --arg status "$status" --arg msg "$msg" '{ts:$ts,agent:$agent,role:$role,kind:$kind,message:($status+" "+$msg)}' >> "$EVENTS_FILE"
}

status=success
{
  printf '[%s] backlog sync start\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  shopt -s nullglob
  files=($BACKLOG_GLOB)
  if ((${#files[@]} == 0)); then
    printf '[%s] no backlog files matched glob %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$BACKLOG_GLOB"
  fi
  for file in "${files[@]}"; do
    printf '[%s] syncing %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$file"
    if ! scripts/backlog/sync.sh "$file"; then
      status=failure
      printf '[%s] sync failed for %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$file"
    fi
  done
  shopt -u nullglob
  printf '[%s] backlog sync finished (%s)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$status"
} | tee -a "$LOG_FILE"

emit_event "$status" "$BACKLOG_GLOB"

[[ "$status" == failure ]] && exit 1 || exit 0
