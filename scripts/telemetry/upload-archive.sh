#!/usr/bin/env bash
set -euo pipefail

: "${S3_BUCKET:?S3_BUCKET is required}"
AWS_CMD=${AWS_CMD:-aws}
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/telemetry/archive"
PREFIX=${S3_PREFIX:-ae-telemetry}

if ! command -v "$AWS_CMD" >/dev/null 2>&1; then
  echo "Required command not found: $AWS_CMD" >&2
  exit 2
fi

shopt -s nullglob
files=($ARCHIVE_DIR/*.ndjson)
if ((${#files[@]} == 0)); then
  echo "No archive files to upload"
  exit 0
fi

for file in "${files[@]}"; do
  key="$PREFIX/$(basename "$file")"
  echo "Uploading $file -> s3://$S3_BUCKET/$key"
  "$AWS_CMD" s3 cp "$file" "s3://$S3_BUCKET/$key"
  if [[ "${DELETE_AFTER_UPLOAD:-0}" == "1" ]]; then
    rm -f "$file"
  fi
done
