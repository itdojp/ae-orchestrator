#!/usr/bin/env bash
set -euo pipefail

# One-shot smoke runner for CI/local verification.
# Seeds labels, ensures the smoke issue is queued, runs one watcher cycle, then verifies.
# Usage:
#   GH_REPO=owner/repo AGENT_ROLE=role:IMPL-MED-1 scripts/smoke/once.sh [options]
# Options:
#   --mark-done       Success時に status:done を付与してキューをクリーンアップ (default off)
#   --no-mark-done    --mark-done を無効化
#   --issue <num>     既存の Issue を対象にスモーク (デフォルトは SMOKE issue を作成/再利用)
#   --timeout <sec>   検証時のタイムアウト (default: env TIMEOUT or 90)
#   --sleep <sec>     検証時のポーリング間隔 (default: env SLEEP or 3)
#   --help            使い方を表示

: "${GH_REPO:?GH_REPO is required (e.g. owner/repo)}"
: "${AGENT_ROLE:?AGENT_ROLE is required (e.g. role:IMPL-MED-1)}"

MARK_DONE=0
TARGET_ISSUE=""
TIMEOUT=${TIMEOUT:-90}
SLEEP=${SLEEP:-3}
WATCH_INTERVAL=${WATCH_INTERVAL:-3}
PREP_TIMEOUT=${PREP_TIMEOUT:-1}
PREP_SLEEP=${PREP_SLEEP:-1}

while (($#)); do
  case "$1" in
    --mark-done) MARK_DONE=1; shift;;
    --no-mark-done) MARK_DONE=0; shift;;
    --issue) TARGET_ISSUE="${2:?issue-number required}"; shift 2;;
    --timeout) TIMEOUT="${2:?seconds required}"; shift 2;;
    --sleep) SLEEP="${2:?seconds required}"; shift 2;;
    --help|-h)
      cat <<USAGE
Usage: $0 [--mark-done|--no-mark-done] [--issue <num>] [--timeout <sec>] [--sleep <sec>]
USAGE
      exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
done

for c in gh jq; do
  command -v "$c" >/dev/null 2>&1 || { echo "Required command not found: $c" >&2; exit 2; }
done

if [[ -x scripts/admin/seed-labels.sh ]]; then
  DRY_RUN=0 GH_REPO="$GH_REPO" scripts/admin/seed-labels.sh >/dev/null || true
fi

echo "[smoke-once] GH_REPO=$GH_REPO role=$AGENT_ROLE interval=$WATCH_INTERVAL mark_done=$MARK_DONE issue=${TARGET_ISSUE:-new} timeout=$TIMEOUT sleep=$SLEEP"

pre_flags=()
[[ -n "$TARGET_ISSUE" ]] && pre_flags+=(--issue "$TARGET_ISSUE")
TIMEOUT="$PREP_TIMEOUT" SLEEP="$PREP_SLEEP" scripts/smoke/impl1.sh "${pre_flags[@]}" >/dev/null 2>&1 || true

WATCH_INTERVAL="$WATCH_INTERVAL" scripts/connector/watch.sh --once || true

post_flags=()
[[ -n "$TARGET_ISSUE" ]] && post_flags+=(--issue "$TARGET_ISSUE")
(( MARK_DONE == 1 )) && post_flags+=(--mark-done)
TIMEOUT="$TIMEOUT" SLEEP="$SLEEP" scripts/smoke/impl1.sh "${post_flags[@]}"
