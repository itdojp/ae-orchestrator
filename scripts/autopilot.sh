#!/usr/bin/env bash
set -euo pipefail
: "${GH_REPO:?}"; : "${ZELLIJ_SESSION:?}"; issue="${1:?issue-number required}"
for c in gh jq zellij; do command -v "$c" >/dev/null 2>&1 || { echo "Required: $c" >&2; exit 2; }; done
FEED_TEXT=${CODEX_AUTOPILOT_FEED_TEXT:-"Continue with the next smallest task (code→test→commit→PR→progress). Keep scope tight. 続けて。次の最小タスクを実装→テスト→コミット→Draft PR更新→Issueへ進捗投稿。"}
INTERVAL=${CODEX_AUTOPILOT_INTERVAL:-60}; MAX_FEEDS=${CODEX_AUTOPILOT_MAX_FEEDS:-240}; COOLDOWN=${CODEX_AUTOPILOT_COOLDOWN:-180}; STOP_LABELS=${CODEX_AUTOPILOT_STOP_LABELS:-"status:review status:done status:blocked autopilot:off"}
FEEDS=("$FEED_TEXT" "Proceed to the next minimal step; update the Issue with progress." "Advance one small task; avoid scope creep; keep diffs small.")
labels_has_stop(){ local j="$1"; for s in $STOP_LABELS; do printf '%s' "$j" | jq -e --arg s "$s" '.labels[]?.name==$s' >/dev/null && return 0; done; return 1; }
effective_interval(){ local j="$1" b=$INTERVAL; printf '%s' "$j" | jq -e '.labels[]?.name=="autopilot:fast"' >/dev/null && { (( b>30 )) && b=30; }; printf '%s' "$j" | jq -e '.labels[]?.name=="autopilot:slow"' >/dev/null && b=$(( b*3 )); echo "$b"; }
recent_activity(){ local j=$(gh issue view "$issue" --repo "$GH_REPO" --json comments 2>/dev/null||echo '{}'); local last=$(printf '%s' "$j"|jq -r '.comments|(map(.createdAt)|sort|last)//""'); [[ -z "$last" || "$last" == "null" ]] && return 1; local le=$(date -u -d "$last" +%s 2>/dev/null||date -u +%s); local ne=$(date -u +%s); (( ne-le < COOLDOWN )); }
count=0
while true; do
  j=$(gh issue view "$issue" --repo "$GH_REPO" --json state,labels || echo '{}'); state=$(printf '%s' "$j"|jq -r '.state // ""'); [[ "$state" != "OPEN" ]] && break; labels_has_stop "$j" && break; recent_activity && { sleep 10; continue; }
  idx=$(( count % ${#FEEDS[@]} )); msg="${FEEDS[$idx]}"; zellij --session "$ZELLIJ_SESSION" action write-chars -- "$msg" || true; zellij --session "$ZELLIJ_SESSION" action write 13 || true; echo "[autopilot] fed #$issue: $msg"; count=$((count+1)); (( count>=MAX_FEEDS )) && break; eff=$(effective_interval "$j"); jitter=$(( RANDOM % 6 )); sleep $(( eff + jitter ))
done
