#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required}"
: "${AGENT_ROLE:?AGENT_ROLE is required}"
WEBHOOK_URL=${WEBHOOK_URL:-}
MARK_DONE=${MARK_DONE:-1}
LOG_DIR=${LOG_DIR:-/tmp}
LOG_FILE="$LOG_DIR/ae-smoke-${AGENT_ROLE//:/-}.log"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
EVENTS_FILE="$ROOT_DIR/telemetry/events.ndjson"
mkdir -p "$ROOT_DIR/telemetry"

for cmd in jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    exit 2
  fi
done

emit_event(){
  local status="$1" msg="$2" ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  jq -nc --arg ts "$ts" --arg agent "$AGENT_ROLE" --arg role "$AGENT_ROLE" --arg kind "smoke" --arg status "$status" --arg msg "$msg" '{ts:$ts,agent:$agent,role:$role,kind:$kind,message:($status+" "+$msg)}' >> "$EVENTS_FILE"
}

mkdir -p "$LOG_DIR"
status=success
{
  printf '[%s] starting smoke cron run\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if ! MARK_DONE="$MARK_DONE" scripts/smoke/run-periodic.sh; then
    status=failure
    printf '[%s] smoke failure\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    emit_event failure "cron-wrapper"
  else
    printf '[%s] smoke success\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    emit_event success "cron-wrapper"
  fi
  printf '[%s] finished smoke cron run (%s)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$status"
} | tee -a "$LOG_FILE"

if [[ "$status" == failure && -n "$WEBHOOK_URL" ]]; then
  if command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    payload=$(jq -n --arg status "$status" --arg role "$AGENT_ROLE" --arg repo "$GH_REPO" --arg log "$LOG_FILE" --arg time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '{text:"AE smoke run failed",status:$status,role:$role,repo:$repo,log:$log,at:$time}')
    curl -fsS -H 'Content-Type: application/json' -d "$payload" "$WEBHOOK_URL" || true
  else
    printf '[%s] webhook skipped (jq or curl missing)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" | tee -a "$LOG_FILE"
  fi
fi

[[ "$status" == failure ]] && exit 1 || exit 0
