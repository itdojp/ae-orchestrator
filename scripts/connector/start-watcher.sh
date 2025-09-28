#!/usr/bin/env bash
set -euo pipefail

# Helper to launch the watcher with sane defaults for long-running sessions.
# Override any variable by exporting it before invoking this script or by
# passing KEY=VALUE pairs (e.g. GH_REPO=owner/repo ./start-watcher.sh).

# Allow KEY=VALUE args for quick overrides
while (($#)); do
  case "$1" in
    *=*) eval "export $1";;
    --help|-h)
      cat <<USAGE
Usage: ${0##*/} [KEY=VALUE ...]

Example:
  GH_REPO=itdojp/ae-orchestrator AGENT_ROLE=role:IMPL-MED-1 ${0##*/}
USAGE
      exit 0;;
    *) echo "Unknown argument: $1" >&2; exit 1;;
  esac
  shift
done

: "${GH_REPO:=itdojp/ae-orchestrator}"
: "${AGENT_ROLE:=role:IMPL-MED-1}"
: "${WATCH_INTERVAL:=60}"
: "${CODEX_BRIDGE:=zellij}"
: "${ZELLIJ_SESSION:=codex-impl-1}"

export GH_REPO AGENT_ROLE WATCH_INTERVAL CODEX_BRIDGE ZELLIJ_SESSION

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
log_dir="$root_dir/telemetry/logs"
mkdir -p "$log_dir"

log_file="$log_dir/${AGENT_ROLE}.watcher.log"
{
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] starting watcher with:"
  echo "  GH_REPO=$GH_REPO"
  echo "  AGENT_ROLE=$AGENT_ROLE"
  echo "  WATCH_INTERVAL=$WATCH_INTERVAL"
  echo "  CODEX_BRIDGE=$CODEX_BRIDGE"
  [[ "$CODEX_BRIDGE" == "zellij" ]] && echo "  ZELLIJ_SESSION=$ZELLIJ_SESSION"
} | tee -a "$log_file"

check_auth_script="$root_dir/scripts/admin/check-gh-auth.sh"
if [[ -x "$check_auth_script" ]]; then
  if ! "$check_auth_script" >>"$log_file" 2>&1; then
    echo "Auth check failed; aborting watcher start (see $log_file)" | tee -a "$log_file"
    exit 1
  fi
fi

if [[ "$CODEX_BRIDGE" == "zellij" ]]; then
  ensure_script="$root_dir/scripts/runner/ensure-zellij.sh"
  if [[ -x "$ensure_script" ]]; then
    if ! "$ensure_script" >>"$log_file" 2>&1; then
      status=$?
      case $status in
        1)
          echo "Zellij session $ZELLIJ_SESSION not found; create it (e.g. 'zellij attach --create $ZELLIJ_SESSION')" | tee -a "$log_file"
          ;;
        2)
          echo "Cleaned exited Zellij session $ZELLIJ_SESSION; recreate it before restarting" | tee -a "$log_file"
          ;;
        *)
          echo "ensure-zellij returned exit=$status" | tee -a "$log_file"
          ;;
      esac
      exit $status
    fi
  fi
fi

eval "cd '$root_dir' && exec bash scripts/connector/watch.sh"
