#!/usr/bin/env bash
# Minimal agent recipe for the Webhook Relay bin:
#   create a bin -> print the URL to send webhooks to -> wait for one -> show it.
# No account, API key, or CLI required. Requires: curl, jq.
#
# Usage: ./agent-recipe.sh [timeout_seconds]
set -euo pipefail

B="https://bin.webhookrelay.com"
TIMEOUT="${1:-120}"

# 1. Create a bin; the reply carries the ingest, browser and long-poll URLs.
CREATED=$(curl -fsS -X POST "$B/v1/bins")
BIN=$(echo "$CREATED" | jq -r .id)

echo "Bin created: $BIN"
echo "Send your webhook to:  $(echo "$CREATED" | jq -r .url)"
echo "Inspect in a browser:  $(echo "$CREATED" | jq -r .inspectUrl)"
echo "Waiting up to ${TIMEOUT}s for the first request..."

# 2. Long-poll: each call returns as soon as a request arrives, or after 25s
#    with a nextUrl to keep waiting. No sleep loop needed.
NEXT=$(echo "$CREATED" | jq -r .requestsUrl)
deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  PAGE=$(curl -fsS -m 70 "$NEXT")
  if [ "$(echo "$PAGE" | jq '.requests | length')" -gt 0 ]; then
    echo "Received! First request:"
    echo "$PAGE" | jq '.requests[0]'
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "Timed out after ${TIMEOUT}s — no webhook received." >&2
    curl -fsS -X DELETE "$B/v1/bins/$BIN" >/dev/null || true
    exit 1
  fi
  NEXT=$(echo "$PAGE" | jq -r .nextUrl)
done

# 3. Clean up.
curl -fsS -X DELETE "$B/v1/bins/$BIN" >/dev/null || true
echo "Bin deleted."
