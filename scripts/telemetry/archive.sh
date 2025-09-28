#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TELEMETRY_DIR="$ROOT_DIR/telemetry"
ARCHIVE_DIR="$TELEMETRY_DIR/archive"
EVENTS_FILE="$TELEMETRY_DIR/events.ndjson"
TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
mkdir -p "$ARCHIVE_DIR"

archive_file(){
  local src="$1" prefix="$2"
  [[ -f "$src" ]] || return 0
  [[ -s "$src" ]] || return 0
  local dest="$ARCHIVE_DIR/${prefix}-${TIMESTAMP}.ndjson"
  mv "$src" "$dest"
  : > "$src"
  chmod 0644 "$src" 2>/dev/null || true
  echo "Archived $src -> $dest"
}

archive_file "$EVENTS_FILE" "events"

for log in "$TELEMETRY_DIR"/logs/*.log; do
  [[ -e "$log" ]] || continue
  archive_file "$log" "${log##*/}"
done
