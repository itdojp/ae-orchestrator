#!/usr/bin/env bash
set -euo pipefail

if ! command -v systemctl >/dev/null 2>&1; then
  echo "systemctl not available in this environment" >&2
  exit 1
fi

ROLE="${AGENT_ROLE:-role:IMPL-MED-1}"
TIMERS=(ae-telemetry-archive.timer ae-backlog-sync.timer "ae-smoke@${ROLE}.timer")
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
if [[ ! -d "$UNIT_DIR" ]]; then
  echo "systemd user unit directory not found: $UNIT_DIR" >&2
  echo "Copy the templates under docs/systemd/ into this directory before running." >&2
  exit 1
fi

enable(){
  local timer="$1"
  local service="${timer%.timer}.service"
  if [[ ! -f "$UNIT_DIR/$timer" || ! -f "$UNIT_DIR/$service" ]]; then
    echo "Missing unit: ensure $timer and $service exist in $UNIT_DIR" >&2
    echo "(copy docs/systemd/${timer} と関連する service を配置して daemon-reload してください)" >&2
    return 1
  fi
  echo "Enabling $timer"
  systemctl --user daemon-reload
  systemctl --user enable --now "$timer"
  systemctl --user status "$timer" --no-pager | head -n 20
  echo
}

for timer in "${TIMERS[@]}"; do
  enable "$timer" || echo "Skipped $timer"
done
