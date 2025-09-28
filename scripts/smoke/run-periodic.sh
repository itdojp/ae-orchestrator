#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required}"
: "${AGENT_ROLE:?AGENT_ROLE is required}"
MARK_DONE_FLAG="--mark-done"
[[ "${MARK_DONE:-1}" == "0" ]] && MARK_DONE_FLAG=""

log(){ printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }

log "running smoke for $AGENT_ROLE on $GH_REPO"
if scripts/smoke/impl1.sh $MARK_DONE_FLAG; then
  log "smoke success"
else
  log "smoke failure" >&2
  exit 1
fi
