#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INPUT="${1:-$ROOT_DIR/telemetry/events.ndjson}"
OUTPUT="${2:-$ROOT_DIR/telemetry/report.html}"
[[ -f "$INPUT" ]] || { echo "No telemetry events file: $INPUT" >&2; exit 1; }

TMP=$(mktemp)

TOTAL=$(wc -l <"$INPUT" 2>/dev/null || echo 0)
if (( TOTAL > 0 )); then
  KIND_TABLE=$(jq -sr 'group_by(.kind) | map({kind:.[0].kind, count:length}) | sort_by(-.count)' "$INPUT")
  AGENT_TABLE=$(jq -sr 'group_by(.agent) | map({agent:.[0].agent,count:length,last:(max_by(.ts))}) | sort_by(.agent)' "$INPUT")
else
  KIND_TABLE='[]'
  AGENT_TABLE='[]'
fi

cat > "$TMP" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>AE Telemetry Report</title>
  <style>
    body { font-family: sans-serif; margin: 2rem; }
    table { border-collapse: collapse; margin-bottom: 2rem; }
    th, td { border: 1px solid #ccc; padding: 0.4rem 0.8rem; }
    th { background: #f0f0f0; }
  </style>
</head>
<body>
  <h1>AE Telemetry Report</h1>
  <p>Total events: $TOTAL</p>
  <h2>Counts by kind</h2>
  <table>
    <tr><th>Count</th><th>Kind</th></tr>
HTML

if (( TOTAL > 0 )); then
  jq -r '.[] | "    <tr><td>\(.count)</td><td>\(.kind)</td></tr>"' <<<"$KIND_TABLE" >> "$TMP"
else
  echo "    <tr><td colspan=2>(none)</td></tr>" >> "$TMP"
fi

cat >> "$TMP" <<HTML
  </table>
  <h2>Latest per agent</h2>
  <table>
    <tr><th>Agent</th><th>Events</th><th>Last Kind</th><th>Last Timestamp</th><th>Message</th></tr>
HTML

if (( TOTAL > 0 )); then
  jq -r '.[] | "    <tr><td>\(.agent)</td><td>\(.count)</td><td>\(.last.kind)</td><td>\(.last.ts)</td><td>\(.last.message)</td></tr>"' <<<"$AGENT_TABLE" >> "$TMP"
else
  echo "    <tr><td colspan=5>(none)</td></tr>" >> "$TMP"
fi

cat >> "$TMP" <<HTML
  </table>
</body>
</html>
HTML

mv "$TMP" "$OUTPUT"
echo "Report written to $OUTPUT"
