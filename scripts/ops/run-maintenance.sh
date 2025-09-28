#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TELEMETRY_DIR="$ROOT_DIR/telemetry"
LOG_DIR="$TELEMETRY_DIR/logs"
WEBHOOK_URL=${WEBHOOK_URL:-}

log(){ printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
notify(){
  local status="$1" message="$2"
  [[ -z "$WEBHOOK_URL" ]] && return 0
  if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    log "webhook skipped (jq or curl missing)"
    return 0
  fi
  local payload
  payload=$(jq -n --arg status "$status" --arg msg "$message" --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '{status:$status,message:$msg,at:$ts}')
  curl -fsS -H 'Content-Type: application/json' -d "$payload" "$WEBHOOK_URL" || log "webhook request failed"
}

mkdir -p "$LOG_DIR"
log "maintenance start"

log "→ trimming telemetry"
MAX_LINES=${MAX_LINES:-2000} scripts/telemetry/trim-logs.sh

log "→ archiving telemetry"
scripts/telemetry/archive.sh || log "archive failed"

log "→ generating telemetry report"
report_file="$TELEMETRY_DIR/report-$(date -u '+%Y%m%d-%H%M%S').txt"
scripts/telemetry/report.sh > "$report_file"
log "report written to $report_file"

if [[ "${RUN_SMOKE:-1}" != "0" ]]; then
  log "→ running smoke"
  if ! GH_REPO="${GH_REPO:-itdojp/ae-orchestrator}" AGENT_ROLE="${AGENT_ROLE:-role:IMPL-MED-1}" scripts/smoke/run-periodic.sh; then
    log "smoke failed"
    notify failure "smoke run failed"
  fi
fi

if [[ "${RUN_BACKLOG_SYNC:-0}" == "1" ]]; then
  log "→ syncing backlog"
  if ! GH_REPO="${GH_REPO:-itdojp/ae-orchestrator}" BACKLOG_GLOB="${BACKLOG_GLOB:-scripts/backlog/*.json}" scripts/backlog/run-cron-wrapper.sh; then
    log "backlog sync failed"
    notify failure "backlog sync failed"
  fi
fi

log "maintenance complete"
notify success "run-maintenance completed"
