#!/usr/bin/env bash
# Minimal agent recipe for the Webhook Relay bin:
#   create a bin -> print the URL to send webhooks to -> wait for one -> show it.
# No account, API key, or CLI required. Requires: curl, jq.
#
# Usage: ./agent-recipe.sh [timeout_seconds]
set -euo pipefail

B="https://bin.webhookrelay.com"
TIMEOUT="${1:-120}"

# 1. Create a bin and capture its ID.
BIN=$(curl -fsS -X POST "$B/v1/bins" | jq -r .id)
URL="$B/v1/webhooks/$BIN"

echo "Bin created: $BIN"
echo "Send your webhook to:  $URL"
echo "Inspect in a browser:  https://webhookrelay.com/webhook-bin?bin=$BIN"
echo "Waiting up to ${TIMEOUT}s for the first request..."

# 2. Poll until at least one request arrives (or we time out).
elapsed=0
until [ "$(curl -fsS "$B/v1/bins/$BIN" | jq '.requests | length')" -gt 0 ]; do
  sleep 2
  elapsed=$((elapsed + 2))
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "Timed out after ${TIMEOUT}s — no webhook received." >&2
    curl -fsS -X DELETE "$B/v1/bins/$BIN" >/dev/null || true
    exit 1
  fi
done

# 3. Print the most recent captured request.
echo "Received! Latest request:"
curl -fsS "$B/v1/bins/$BIN" | jq '.requests | sort_by(.receivedAt) | last'

# 4. Clean up.
curl -fsS -X DELETE "$B/v1/bins/$BIN" >/dev/null || true
echo "Bin deleted."
