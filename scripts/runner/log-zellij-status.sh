#!/usr/bin/env bash
set -euo pipefail

SESSION="${ZELLIJ_SESSION:-codex-impl-1}"
AGENT_ROLE_ESCAPED="${AGENT_ROLE:-role:IMPL-MED-1}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT_DIR/telemetry/logs"
LOG_FILE="$LOG_DIR/${AGENT_ROLE_ESCAPED}.watcher.log"
mkdir -p "$LOG_DIR"

TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
{
  echo "[$TIMESTAMP] zellij status dump for session=$SESSION"
  if command -v zellij >/dev/null 2>&1; then
    zellij list-sessions || echo "(zellij list-sessions failed)"
  else
    echo "zellij not installed"
  fi
} >> "$LOG_FILE" 2>&1
