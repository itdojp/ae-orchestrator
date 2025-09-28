#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPORT_DIR="$ROOT_DIR/telemetry"
S3_BUCKET=${S3_BUCKET:-}
S3_PREFIX=${S3_PREFIX:-ae-telemetry-reports}
WEBHOOK_URL=${WEBHOOK_URL:-}
AWS_CMD=${AWS_CMD:-aws}

shopt -s nullglob
reports=($REPORT_DIR/report-*.html $REPORT_DIR/report-*.txt)
if ((${#reports[@]} == 0)); then
  echo "No reports to publish"
  exit 0
fi

if [[ -n "$S3_BUCKET" ]]; then
  if ! command -v "$AWS_CMD" >/dev/null 2>&1; then
    echo "AWS CLI not found, skipping S3 upload" >&2
  else
    for file in "${reports[@]}"; do
      key="$S3_PREFIX/$(basename "$file")"
      echo "Uploading $file -> s3://$S3_BUCKET/$key"
      "$AWS_CMD" s3 cp "$file" "s3://$S3_BUCKET/$key"
    done
  fi
fi

if [[ -n "$WEBHOOK_URL" ]]; then
  if command -v jq >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    latest=$(printf '%s\n' "${reports[@]}" | sort | tail -n 1)
    payload=$(jq -n --arg msg "Telemetry report published" --arg file "$(basename "$latest")" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" '{text:$msg,file:$file,at:$at}')
    curl -fsS -H 'Content-Type: application/json' -d "$payload" "$WEBHOOK_URL" || echo "Webhook send failed" >&2
  else
    echo "Skipping webhook (jq or curl missing)" >&2
  fi
fi
