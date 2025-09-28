#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$ROOT_DIR/telemetry/logs"
EVENTS_FILE="$ROOT_DIR/telemetry/events.ndjson"
STATUS_DIR="$ROOT_DIR/telemetry/status"
MAX_LINES=${MAX_LINES:-2000}
BACKUP_SUFFIX=".bak"

command -v jq >/dev/null 2>&1 || { echo "Required command not found: jq" >&2; exit 2; }

trim_file(){
  local file="$1"
  [[ -f "$file" ]] || return 0
  local lines
  lines=$(wc -l <"$file" 2>/dev/null || echo 0)
  (( lines <= MAX_LINES )) && return 0
  local tmp="$file$BACKUP_SUFFIX"
  tail -n "$MAX_LINES" "$file" > "$tmp"
  mv "$tmp" "$file"
}

mkdir -p "$LOG_DIR" "$STATUS_DIR"
for f in "$LOG_DIR"/*.log; do
  [[ -e "$f" ]] || continue
  trim_file "$f"
done
trim_file "$EVENTS_FILE"

# Statusファイルが肥大化するケースは稀だが、破損回避のため JSON の整形検証を行う
for f in "$STATUS_DIR"/*.json; do
  [[ -e "$f" ]] || continue
  if ! jq empty "$f" >/dev/null 2>&1; then
    echo "Invalid JSON detected in $f" >&2
  fi
done
