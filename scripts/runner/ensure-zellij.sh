#!/usr/bin/env bash
set -euo pipefail

SESSION="${ZELLIJ_SESSION:-codex-impl-1}"
ACTION=${1:-status}

strip_colors(){ perl -pe 's/\e\[[0-9;]*[a-zA-Z]//g'; }
case "$ACTION" in
  status)
    sessions=$(zellij list-sessions 2>/dev/null | strip_colors || true)
    if printf '%s\n' "$sessions" | awk '{print $1}' | grep -Fxq "$SESSION"; then
      echo "session ${SESSION} is active"
      exit 0
    fi
    if printf '%s\n' "$sessions" | grep -F "$SESSION" | grep -q "EXITED"; then
      echo "session ${SESSION} exists but exited; deleting"
      zellij delete-session "$SESSION"
      echo "deleted exited session ${SESSION}"
      exit 2
    fi
    echo "session ${SESSION} not found"
    echo "Run 'zellij attach --create ${SESSION}' in an interactive terminal to recreate it." >&2
    exit 1
    ;;
  delete)
    zellij delete-session "$SESSION"
    ;;
  *)
    echo "Usage: ${0##*/} [status|delete]" >&2
    exit 1
    ;;
esac
