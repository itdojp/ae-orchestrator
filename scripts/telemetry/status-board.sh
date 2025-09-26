#!/usr/bin/env bash
set -euo pipefail
root_dir="$(cd "$(dirname "$0")/../.." && pwd)"; status_dir="$root_dir/telemetry/status"; events_file="$root_dir/telemetry/events.ndjson"
mode=summary; watch_interval=5; tail_lines=20; follow=0
while (($#)); do case "$1" in --summary) mode=summary; shift;; --watch) mode=watch; watch_interval="$2"; shift 2;; --events) mode=events; [[ ${2:-} =~ ^[0-9]+$ ]] && tail_lines="$2" && shift 2 || shift;; --events-follow) mode=events; follow=1; shift;; --help|-h) echo "Usage: $0 [--summary|--watch <sec>|--events [n]|--events-follow]"; exit 0;; *) echo "Unknown: $1"; exit 1;; esac; done
print_summary(){ ls "$status_dir"/*.json >/dev/null 2>&1 || { echo "No agent status files in $status_dir"; return 0; }
  printf '%-12s %-16s %-9s %-7s %-20s %-12s %-10s %-20s\n' AGENT ROLE STATE QUEUE LAST_CYCLE ACTION ISSUE RESULT ACTION_TIME
  for f in $(ls "$status_dir"/*.json | sort); do jq -r '[.agent,.role,.state, (.queue_snapshot|length), .last_cycle_at, .last_action.action, .last_action.issue, .last_action.result, .last_action.at]|@tsv' "$f"|while IFS=$'\t' read -r a r s q lc act is res at; do \
    [[ -z "$is" || "$is" == "null" ]] && is='-'; [[ "$is" != '-' ]] && is="#${is}"; \
    # Compact common result messages for readability
    [[ "$res" == "skipped:cooldown" ]] && res='skip-cooldown'; \
    [[ "$res" == error:* ]] && res='error'; \
    # Truncate overly long results to 20 chars
    [[ ${#res} -gt 20 ]] && res="${res:0:19}…"; \
    printf '%-12s %-16s %-9s %-7s %-20s %-12s %-10s %-20s\n' "$a" "$r" "$s" "$q" "$lc" "$act" "$is" "$res" "$at"; done; done }
print_events(){ [[ -f "$events_file" ]] || { echo "No events ($events_file)"; return 0; }; (( follow )) && tail -n "$tail_lines" -f "$events_file" || tail -n "$tail_lines" "$events_file"; }
case "$mode" in summary) print_summary;; watch) while true; do clear; date; print_summary; sleep "$watch_interval"; done;; events) print_events;; esac
