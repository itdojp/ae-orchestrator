#!/usr/bin/env bash
set -euo pipefail

SERVICES=(ae-telemetry-archive ae-backlog-sync)
ROLE="${AGENT_ROLE:-role:IMPL-MED-1}"
SERVICES+=("ae-smoke@${ROLE}")

if command -v systemctl >/dev/null 2>&1; then
  echo "Detected systemctl. Checking timers..."
  systemctl --user list-timers --all | grep -E 'ae-(telemetry|backlog|smoke)' || echo "No ae-* timers registered"
  echo
  echo "Commands to enable timers:"
  echo "systemctl --user enable --now ae-telemetry-archive.timer"
  echo "systemctl --user enable --now ae-backlog-sync.timer"
  echo "systemctl --user enable --now ae-smoke@${ROLE}.timer"
else
  cat <<INFO
systemctl not available. To enable timers manually (on supported systems):
  systemctl --user enable --now ae-telemetry-archive.timer
  systemctl --user enable --now ae-backlog-sync.timer
  systemctl --user enable --now ae-smoke@${ROLE}.timer
INFO
fi
