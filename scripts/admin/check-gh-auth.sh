#!/usr/bin/env bash
set -euo pipefail

if gh auth status --exit-status >/dev/null 2>&1; then
  echo "GitHub auth: ok"
else
  echo "GitHub auth: FAILED" >&2
  gh auth status || true
  exit 1
fi

if codex login status >/dev/null 2>&1; then
  echo "Codex auth: ok"
else
  echo "Codex auth: UNKNOWN (codex login status unsupported or failed)" >&2
fi
