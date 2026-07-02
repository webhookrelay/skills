#!/usr/bin/env bash
# wait-for-email.sh — create a temporary inbox (or reuse a bucket) and wait for
# incoming mail, printing each message as it arrives.
#
# Requires: the `relay` CLI (logged in) and `jq`.
# Usage:
#   ./wait-for-email.sh            # create a throwaway inbox and wait
#   ./wait-for-email.sh my-bucket  # wait on an existing bucket
set -euo pipefail

BUCKET="${1:-}"

if [ -z "$BUCKET" ]; then
  JSON=$(relay email create --json)
  ADDR=$(printf '%s' "$JSON" | jq -r .email_address)
  BUCKET=$(printf '%s' "$JSON" | jq -r .bucket_name)
  echo "Temporary address: $ADDR"
  echo "Delete it later with: relay bucket rm $BUCKET"
  echo
fi

echo "Waiting for email in bucket '$BUCKET' (Ctrl-C to stop)…"
# --follow blocks and prints each new email (sender + subject) as it lands.
# Swap for `--body` to stream the raw parsed-email JSON instead.
relay events --bucket "$BUCKET" --follow
