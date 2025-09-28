#!/usr/bin/env bash
set -euo pipefail

issue="${1:-}" || true
if [[ -z "$issue" ]]; then
  cat <<USAGE
Usage: ${0##*/} <issue-number>
Runs scripts/runner/exec.sh against the issue using CODEX_EXEC=1 to verify non-interactive Codex.
USAGE
  exit 1
fi

: "${GH_REPO:?GH_REPO is required}"
AGENT_WORKDIR="${AGENT_WORKDIR:-$(git rev-parse --show-toplevel)}"
export GH_REPO AGENT_WORKDIR CODEX_EXEC=1

scripts/runner/exec.sh "$issue"
