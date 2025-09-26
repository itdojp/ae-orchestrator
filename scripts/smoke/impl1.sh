#!/usr/bin/env bash
set -euo pipefail

# Smoke test for IMPL-1 watcher/runner pipeline
# - Creates (or reuses) a SMOKE issue labeled with AGENT_ROLE and status:ready
# - Waits until watcher transitions it to status:running (idempotency) and posts /start
#
# Requirements:
#   env: GH_REPO, AGENT_ROLE
#   tools: gh, jq

: "${GH_REPO:?GH_REPO is required (e.g. owner/repo)}"
: "${AGENT_ROLE:?AGENT_ROLE is required (e.g. role:IMPL-MED-1)}"

for c in gh jq; do command -v "$c" >/dev/null 2>&1 || { echo "Required command not found: $c" >&2; exit 2; }; done

TITLE="SMOKE: IMPL-1 watcher/runner pipeline"
BODY="Smoke test issue for watcher/runner pipeline. This issue is created by scripts/smoke/impl1.sh."
TIMEOUT=${TIMEOUT:-180}
SLEEP=${SLEEP:-5}

echo "[smoke] Target repo: $GH_REPO, role: $AGENT_ROLE"

# Find existing SMOKE issue or create a new one
existing=$(gh issue list --repo "$GH_REPO" --search "$TITLE in:title" --state open --json number,title,labels 2>/dev/null | jq -r 'map(select(.title==env.TITLE))|.[0].number // empty')
if [[ -n "${existing:-}" ]]; then
  issue="$existing"
  echo "[smoke] Using existing issue #$issue"
else
  issue_url=$(gh issue create --repo "$GH_REPO" --title "$TITLE" --body "$BODY" --label "$AGENT_ROLE")
  issue="${issue_url##*/}"
  echo "[smoke] Created issue #$issue"
fi

# Ensure labels: role + status:ready (remove status:running to re-queue if present)
gh issue edit "$issue" --repo "$GH_REPO" --add-label "$AGENT_ROLE" >/dev/null || true
gh issue edit "$issue" --repo "$GH_REPO" --remove-label status:running >/dev/null 2>&1 || true
gh issue edit "$issue" --repo "$GH_REPO" --add-label status:ready >/dev/null || true
echo "[smoke] Labeled #$issue with: $AGENT_ROLE, status:ready"

echo "[smoke] Waiting for watcher to transition to status:running and post /start ..."
start_ts=$(date -u +%s)
found_running=0
found_start_comment=0

while true; do
  now=$(date -u +%s)
  (( now - start_ts > TIMEOUT )) && { echo "[smoke] Timeout after ${TIMEOUT}s"; break; }

  j=$(gh issue view "$issue" --repo "$GH_REPO" --json labels,comments --jq '{labels:[.labels[].name], comments:(.comments // [])}') || j='{}'
  if printf '%s' "$j" | jq -e '.labels | index("status:running")' >/dev/null; then
    (( found_running==0 )) && echo "[smoke] Detected status:running label"
    found_running=1
  fi
  if printf '%s' "$j" | jq -e '.comments | map(.body=="/start") | any' >/dev/null; then
    (( found_start_comment==0 )) && echo "[smoke] Detected /start comment"
    found_start_comment=1
  fi

  if (( found_running==1 && found_start_comment==1 )); then
    echo "[smoke] SUCCESS: watcher/runner pipeline responded"
    exit 0
  fi
  sleep "$SLEEP"
done

echo "[smoke] FAILED: conditions not met (running=${found_running}, start=${found_start_comment})"
exit 1

