#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FILE="${1:-$ROOT_DIR/telemetry/events.ndjson}"
[[ -f "$FILE" ]] || { echo "No telemetry events file: $FILE" >&2; exit 1; }

TOTAL=$(wc -l <"$FILE" 2>/dev/null || echo 0)
echo "events: $TOTAL"

echo "\ncounts by kind:"
if (( TOTAL > 0 )); then
  jq -r '.kind' "$FILE" | sort | uniq -c | sort -nr
else
  echo "(none)"
fi

echo "\nlatest per agent:"
if (( TOTAL > 0 )); then
  jq -sr 'group_by(.agent) | sort_by(.[0].agent) | map({agent: .[0].agent, count: length, last: (max_by(.ts))}) | .[] | "\(.agent)\tcount=\(.count)\tlast=\(.last.kind) @\(.last.ts) \(.last.message)"' "$FILE"
else
  echo "(none)"
fi
