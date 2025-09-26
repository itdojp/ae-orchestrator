#!/usr/bin/env bash
set -euo pipefail

# One-shot smoke runner for CI: prepare issue, run watcher once, then verify.
# Usage:
#   GH_REPO=owner/repo AGENT_ROLE=role:IMPL-MED-1 scripts/smoke/once.sh [--mark-done]

: "${GH_REPO:?GH_REPO is required (e.g. owner/repo)}"
: "${AGENT_ROLE:?AGENT_ROLE is required (e.g. role:IMPL-MED-1)}"

MARK_DONE=0
TIMEOUT=${TIMEOUT:-90}
SLEEP=${SLEEP:-3}
WATCH_INTERVAL=${WATCH_INTERVAL:-3}

while (($#)); do
  case "$1" in
    --mark-done) MARK_DONE=1; shift;;
    --help|-h) echo "Usage: $0 [--mark-done]"; exit 0;;
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

echo "[smoke-once] GH_REPO=$GH_REPO role=$AGENT_ROLE interval=$WATCH_INTERVAL mark_done=$MARK_DONE"

# Ensure the issue exists and is queued as ready before running watcher once
scripts/smoke/impl1.sh >/dev/null 2>&1 || true

# Run a single watcher cycle to dispatch
WATCH_INTERVAL="$WATCH_INTERVAL" scripts/connector/watch.sh --once || true

# Verify success and optionally mark done
if (( MARK_DONE == 1 )); then
  scripts/smoke/impl1.sh --mark-done
else
  scripts/smoke/impl1.sh
fi

