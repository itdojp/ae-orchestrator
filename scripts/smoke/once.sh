#!/usr/bin/env bash
set -euo pipefail

# One-shot smoke runner for CI: prepare issue, run watcher once, then verify.
# Usage:
#   GH_REPO=owner/repo AGENT_ROLE=role:IMPL-MED-1 scripts/smoke/once.sh [--mark-done] [--issue N] [--timeout SEC] [--sleep SEC]

: "${GH_REPO:?GH_REPO is required (e.g. owner/repo)}"
: "${AGENT_ROLE:?AGENT_ROLE is required (e.g. role:IMPL-MED-1)}"

MARK_DONE=0
TIMEOUT=${TIMEOUT:-90}
SLEEP=${SLEEP:-3}
WATCH_INTERVAL=${WATCH_INTERVAL:-3}
TARGET_ISSUE=""

while (($#)); do
  case "$1" in
    --mark-done) MARK_DONE=1; shift;;
    --issue) TARGET_ISSUE="${2:?issue-number required}"; shift 2;;
    --timeout) TIMEOUT="${2:?seconds required}"; shift 2;;
    --sleep) SLEEP="${2:?seconds required}"; shift 2;;
    --help|-h) echo "Usage: $0 [--mark-done] [--issue <num>] [--timeout <sec>] [--sleep <sec>]"; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

req(){ command -v "$1" >/dev/null 2>&1 || { echo "Required: $1" >&2; exit 2; }; }
for c in gh jq; do req "$c"; done

# Ensure labels exist (idempotent)
if [[ -x scripts/admin/seed-labels.sh ]]; then
  DRY_RUN=0 GH_REPO="$GH_REPO" scripts/admin/seed-labels.sh >/dev/null || true
fi

export GH_REPO AGENT_ROLE TIMEOUT SLEEP

# Prepare or reuse the standard smoke issue (impl1.sh handles creation/labeling)
# Run watcher once to process the queue, then verify via impl1.sh

echo "[smoke-once] GH_REPO=$GH_REPO role=$AGENT_ROLE interval=$WATCH_INTERVAL mark_done=$MARK_DONE issue=${TARGET_ISSUE:-} timeout=$TIMEOUT sleep=$SLEEP"

# Ensure the issue exists and is queued as ready before running watcher once
pre_flags=()
[[ -n "$TARGET_ISSUE" ]] && pre_flags+=(--issue "$TARGET_ISSUE")
[[ -n "$TIMEOUT" ]] && export TIMEOUT
[[ -n "$SLEEP" ]] && export SLEEP
scripts/smoke/impl1.sh "${pre_flags[@]}" >/dev/null 2>&1 || true

# Run a single watcher cycle to dispatch
WATCH_INTERVAL="$WATCH_INTERVAL" scripts/connector/watch.sh --once || true

# Verify success and optionally mark done
post_flags=( )
[[ -n "$TARGET_ISSUE" ]] && post_flags+=(--issue "$TARGET_ISSUE")
if (( MARK_DONE == 1 )); then post_flags+=(--mark-done); fi
scripts/smoke/impl1.sh "${post_flags[@]}"
