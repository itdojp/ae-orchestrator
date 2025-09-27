#!/usr/bin/env bash
set -euo pipefail

# Seed commonly used labels in the target repo.
# Usage:
#   GH_REPO=owner/repo scripts/admin/seed-labels.sh
#
# Env:
#   GH_REPO (required)
#   DRY_RUN=1 to only print actions

: "${GH_REPO:?GH_REPO is required (e.g. owner/repo)}"

for c in gh jq; do command -v "$c" >/dev/null 2>&1 || { echo "Required command not found: $c" >&2; exit 2; }; done

DRY_RUN=${DRY_RUN:-0}

# name|color|description
labels=(
  "status:running|C2F970|Issue picked up by watcher/runner; avoid re-dispatch"
  "status:review|0E8A16|Awaiting review"
  "status:done|5319E7|Completed"
  "status:blocked|B60205|Blocked; needs attention"
  "autopilot:off|BFD4F2|Disable autopilot for this issue"
  "autopilot:fast|0CF|Autopilot faster feed interval"
  "autopilot:slow|0366D6|Autopilot slower feed interval"
)

existing=$(gh label list --repo "$GH_REPO" --limit 300 --json name | jq -r '.[].name')

ensure_label(){
  local name="$1" color="$2" desc="$3"
  if printf '%s\n' "$existing" | grep -Fxq -- "$name"; then
    echo "exists: $name"
  else
    echo "create: $name (#$color) — $desc"
    if (( DRY_RUN == 0 )); then
      gh label create "$name" --repo "$GH_REPO" --color "$color" --description "$desc" >/dev/null
    fi
  fi
}

for entry in "${labels[@]}"; do
  IFS='|' read -r name color desc <<<"$entry"
  ensure_label "$name" "$color" "$desc"
done

echo "done."

