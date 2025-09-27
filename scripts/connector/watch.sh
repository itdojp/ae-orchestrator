#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required (e.g. owner/repo)}"
: "${AGENT_ROLE:?AGENT_ROLE is required (e.g. role:IMPL-MED-1)}"
WATCH_INTERVAL="${WATCH_INTERVAL:-60}"

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
log_dir="$root_dir/telemetry/logs"
status_dir="$root_dir/telemetry/status"
events_file="$root_dir/telemetry/events.ndjson"
mkdir -p "$log_dir" "$status_dir"

agent_name="${AGENT_NAME:-$AGENT_ROLE}"
log_file="$log_dir/${agent_name}.log"
status_file="$status_dir/${agent_name}.json"

req() { command -v "$1" >/dev/null 2>&1 || { echo "Required command not found: $1" >&2; exit 2; }; }
for c in gh jq; do req "$c"; done

now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { local line="[$(now)] [$agent_name] $*"; echo "$line" | tee -a "$log_file" >/dev/null; }
emit() { jq -nc --arg ts "$(now)" --arg agent "$agent_name" --arg role "$AGENT_ROLE" --arg kind "$1" --arg msg "$2" '{ts:$ts,agent:$agent,role:$role,kind:$kind,message:$msg}' >> "$events_file"; }
write_status(){
  local state="$1" cycle_ts="$2" issues_json="$3" act_issue="$4" act_kind="$5" act_res="$6" act_ts="$7"
  jq -nc --arg agent "$agent_name" --arg role "$AGENT_ROLE" --arg repo "$GH_REPO" \
    --arg state "$state" --arg ts "$cycle_ts" --argjson issues "$issues_json" \
    --arg act_issue "$act_issue" --arg act_kind "$act_kind" --arg act_res "$act_res" --arg act_ts "$act_ts" \
    '{agent:$agent,role:$role,repo:$repo,state:$state,last_cycle_at:$ts,queue_snapshot:$issues,last_action:{at:$act_ts,action:$act_kind,result:$act_res,issue:(if $act_issue=="" then null else ($act_issue|tonumber) end)}}' > "$status_file"
}

trap 'code=$?; ts=$(now); log "Watcher stopping (exit=$code)"; emit shutdown "exit=$code"; write_status stopped "$ts" '[]' "" idle stopped "$ts"; exit $code' EXIT

log "Watcher started for $agent_name ($AGENT_ROLE) on $GH_REPO (interval=${WATCH_INTERVAL}s)"
emit startup "interval=${WATCH_INTERVAL}s"
write_status running "$(now)" '[]' "" startup ready "$(now)"


is_global_paused(){
  gh issue list --repo "$GH_REPO" --state open \
    --label orchestrator:control --label orchestrator:paused \
    --json totalCount -q '.totalCount>0' >/dev/null 2>&1
}

is_role_paused(){
  local raw_role="${AGENT_ROLE#role:}"
  gh issue list --repo "$GH_REPO" --state open \
    --label orchestrator:control --label "paused:role:${raw_role}" \
    --json totalCount -q '.totalCount>0' >/dev/null 2>&1 || \
  gh issue list --repo "$GH_REPO" --state open \
    --label orchestrator:control --label "paused:${AGENT_ROLE}" \
    --json totalCount -q '.totalCount>0' >/dev/null 2>&1
}
while true; do
  cycle_ts="$(now)"
  if is_global_paused; then
    log "Global pause active (orchestrator:paused) — skipping cycle"
    emit idle "paused=global"
    write_status running "$cycle_ts" "[]" "" idle paused-global "$cycle_ts"
    sleep "$WATCH_INTERVAL"; continue
  fi
  if is_role_paused; then
    log "Role pause active — skipping cycle"
    emit idle "paused=role"
    write_status running "$cycle_ts" "[]" "" idle paused-role "$cycle_ts"
    sleep "$WATCH_INTERVAL"; continue
  fi
  # Collect READY issues for the role and drop ones already marked status:running to avoid re-dispatch
  if issues_json=$(gh issue list --repo "$GH_REPO" --label "$AGENT_ROLE" --label status:ready --json number,title,labels); then
    :
  else
    rc=$?
    log "Failed to list ready issues (exit=$rc); retrying after sleep"
    emit error "list-ready exit=$rc"
    sleep "$WATCH_INTERVAL"
    continue
  fi
  filtered_json=$(jq '[.[] | select(((.labels // []) | map(.name)) | index("status:running") | not)]' <<<"$issues_json")
  mapfile -t issues < <(jq -r '.[].number' <<<"$filtered_json")
  issue_snapshot="$(jq -c 'map(.number)' <<<"$filtered_json")"
  total_ready=$(jq 'length' <<<"$issues_json")
  pending_ready=$(jq 'length' <<<"$filtered_json")
  skipped_ready=$(( total_ready - pending_ready ))
  if (( skipped_ready > 0 )); then
    skipped_list=$(jq -r '[.[] | select(((.labels // []) | map(.name)) | index("status:running")) | .number] | join(", ")' <<<"$issues_json")
    log "Skipping ${skipped_ready} ready issue(s) already labeled status:running: ${skipped_list:-none}"
    emit idle "queue-skip count=${skipped_ready} issues=${skipped_list:-none}"
  fi

  if (( pending_ready == 0 )); then
    if (( total_ready == 0 )); then
      log "No ready issues found; sleeping ${WATCH_INTERVAL}s"
      emit idle "queue=0"
      write_status running "$cycle_ts" "$issue_snapshot" "" idle queue-empty "$cycle_ts"
    else
      log "Ready issues already running; sleeping ${WATCH_INTERVAL}s"
      emit idle "queue-running"
      write_status running "$cycle_ts" "$issue_snapshot" "" idle queue-running "$cycle_ts"
    fi
    sleep "$WATCH_INTERVAL"; continue
  fi

  log "Found ${pending_ready} ready issue(s): ${issues[*]}"; emit queue "count=${pending_ready} issues=${issues[*]}"
  for issue in "${issues[@]}"; do
    act_ts="$(now)"; log "Dispatching /start to #$issue"
    if gh issue comment "$issue" --repo "$GH_REPO" --body "/start"; then
      emit dispatch "issue=$issue action=/start"; log "Dispatched /start to #$issue successfully"
      if gh issue edit "$issue" --repo "$GH_REPO" --remove-label status:ready >/dev/null 2>&1; then
        log "Removed status:ready from #$issue"
      else
        rc=$?
        log "Unable to remove status:ready from #$issue (exit=$rc)"
      fi
      if gh issue edit "$issue" --repo "$GH_REPO" --add-label status:running >/dev/null 2>&1; then
        log "Applied status:running to #$issue"
      else
        rc=$?
        log "Unable to add status:running to #$issue (exit=$rc)"
      fi
      if [[ "${CODEX_BRIDGE:-}" == "zellij" && -n "${ZELLIJ_SESSION:-}" ]]; then scripts/runner/bridge-zellij.sh "$issue" || true; fi
      if [[ "${CODEX_EXEC:-}" == "1" && -n "${AGENT_WORKDIR:-}" ]]; then scripts/runner/exec.sh "$issue" || true; fi
      if [[ "${CODEX_AUTOPILOT:-}" == "1" && -n "${ZELLIJ_SESSION:-}" ]]; then scripts/autopilot.sh "$issue" >/dev/null 2>&1 & disown || true; fi
      write_status running "$cycle_ts" "$issue_snapshot" "$issue" "/start" ok "$act_ts"
    else
      rc=$?; emit error "issue=$issue action=/start exit=$rc"; log "Failed to dispatch /start to #$issue (exit=$rc)"; write_status running "$cycle_ts" "$issue_snapshot" "$issue" "/start" "error:$rc" "$act_ts"
    fi
  done
  sleep "$WATCH_INTERVAL"
done
