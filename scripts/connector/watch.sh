#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required (e.g. owner/repo)}"
: "${AGENT_ROLE:?AGENT_ROLE is required (e.g. role:IMPL-MED-1)}"
WATCH_INTERVAL="${WATCH_INTERVAL:-60}"
DISPATCH_COOLDOWN_SECONDS="${DISPATCH_COOLDOWN_SECONDS:-600}"

# Options
RUN_ONCE=0
while (($#)); do
  case "$1" in
    --once) RUN_ONCE=1; shift;;
    --help|-h) echo "Usage: $0 [--once]"; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

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

while true; do
  cycle_ts="$(now)"
  mapfile -t issues < <(gh issue list --repo "$GH_REPO" --label "$AGENT_ROLE" --label status:ready --json number,title | jq -r '.[].number')
  issue_snapshot="$(printf '%s\n' "${issues[@]:-}" | jq -R -s 'split("\n") | map(select(length>0) | tonumber)')"

  if ((${#issues[@]} == 0)); then
    log "No ready issues found; sleeping ${WATCH_INTERVAL}s"; emit idle "queue=0"; write_status running "$cycle_ts" "$issue_snapshot" "" idle queue-empty "$cycle_ts"; sleep "$WATCH_INTERVAL"; continue
  fi

  log "Found ${#issues[@]} ready issue(s): ${issues[*]}"; emit queue "count=${#issues[@]} issues=${issues[*]}"
  for issue in "${issues[@]}"; do
    act_ts="$(now)"; log "Dispatching /start to #$issue"
    # Cooldown: skip if a recent '/start' exists within the cooldown window
    last_start_ts=$(gh issue view "$issue" --repo "$GH_REPO" --json comments 2>/dev/null | jq -r '.comments | map(select(.body=="/start") | .createdAt) | sort | last // empty') || last_start_ts=""
    if [[ -n "$last_start_ts" && "$last_start_ts" != "null" ]]; then
      last_epoch=$(date -u -d "$last_start_ts" +%s 2>/dev/null || date -u +%s)
      now_epoch=$(date -u +%s)
      if (( now_epoch - last_epoch < DISPATCH_COOLDOWN_SECONDS )); then
        log "Skipping dispatch to #$issue due to cooldown (last /start at $last_start_ts)"; emit skip "issue=$issue reason=cooldown last_start=$last_start_ts";
        write_status running "$cycle_ts" "$issue_snapshot" "$issue" "/start" skipped:cooldown "$act_ts"; continue
      fi
    fi
    if gh issue comment "$issue" --repo "$GH_REPO" --body "/start"; then
      emit dispatch "issue=$issue action=/start"; log "Dispatched /start to #$issue successfully"
      # Prevent repeated dispatching: move issue out of READY queue
      # 1) Remove status:ready (best-effort)
      if gh issue edit "$issue" --repo "$GH_REPO" --remove-label status:ready >/dev/null 2>&1; then
        emit state "issue=$issue label:removed status:ready"; log "Removed label from #$issue: status:ready"
      else
        emit warn "issue=$issue remove status:ready failed"; log "Warning: failed to remove status:ready for #$issue"
      fi
      # 2) Add status:running only if the label exists in the repo
      if gh label list --repo "$GH_REPO" --limit 200 --json name | jq -e '.[] | select(.name=="status:running")' >/dev/null 2>&1; then
        if gh issue edit "$issue" --repo "$GH_REPO" --add-label status:running >/dev/null 2>&1; then
          emit state "issue=$issue label:added status:running"; log "Added label to #$issue: status:running"
        else
          emit warn "issue=$issue add status:running failed"; log "Warning: failed to add status:running for #$issue"
        fi
      else
        emit warn "issue=$issue label status:running not defined"; log "Label 'status:running' not found in repo; skipped adding to #$issue"
      fi
      if [[ "${CODEX_BRIDGE:-}" == "zellij" && -n "${ZELLIJ_SESSION:-}" ]]; then scripts/runner/bridge-zellij.sh "$issue" || true; fi
      if [[ "${CODEX_EXEC:-}" == "1" && -n "${AGENT_WORKDIR:-}" ]]; then scripts/runner/exec.sh "$issue" || true; fi
      if [[ "${CODEX_AUTOPILOT:-}" == "1" && -n "${ZELLIJ_SESSION:-}" ]]; then scripts/autopilot.sh "$issue" >/dev/null 2>&1 & disown || true; fi
      write_status running "$cycle_ts" "$issue_snapshot" "$issue" "/start" ok "$act_ts"
    else
      rc=$?; emit error "issue=$issue action=/start exit=$rc"; log "Failed to dispatch /start to #$issue (exit=$rc)"; write_status running "$cycle_ts" "$issue_snapshot" "$issue" "/start" "error:$rc" "$act_ts"
    fi
  done
  # Stop after a single cycle if requested
  if (( RUN_ONCE == 1 )); then log "Run-once mode: exiting after one cycle"; emit shutdown "mode=once"; write_status stopped "$(now)" "$issue_snapshot" "" stopped once "$(now)"; break; fi
  sleep "$WATCH_INTERVAL"
done
