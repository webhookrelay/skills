---
name: webhook-debug
description: >-
  Capture, inspect and debug webhooks with a free, no-signup Webhook Relay bin —
  a public URL that records any HTTP request sent to it so you can see the exact
  method, headers, query and body a provider sends. Create a bin, hand its URL
  to any sender (Stripe, GitHub, Shopify, CI, your own code), then read the
  captured requests back as JSON, stream them live, configure the response the
  bin returns (status/body/headers/delay/probabilistic failures), and verify
  HMAC signatures. No CLI, account, or API key required. Triggers: "test a
  webhook", "get a webhook URL", "inspect/debug an incoming webhook", "what is
  my provider sending", "capture HTTP requests", "webhook tester / request bin",
  "mock a webhook response", "verify a webhook (HMAC) signature", "is my Stripe/
  GitHub webhook signature valid". Everything runs against the public API at
  https://bin.webhookrelay.com — see https://webhookrelay.com/webhook-bin.md.
---

# Webhook debugging with a Webhook Relay bin

A **bin** is a throwaway public endpoint that captures every HTTP request sent
to it. Point a webhook sender at the bin's URL, then read back exactly what
arrived — method, headers, query string, body, sender IP, and the status the bin
returned. Use it to see what a provider actually sends, reproduce a payload, or
mock an endpoint's response while you build the real handler.

- **API base:** `https://bin.webhookrelay.com`
- **No auth.** No account, API key, or CLI needed. CORS is enabled.
- **Public & temporary.** Anyone with the bin ID can read its requests, and bins
  auto-expire after ~48 hours. **Never send secrets/PII to a bin.**

> When to use this vs. the forwarding skills: a bin only *captures and displays*
> requests. To actually deliver provider webhooks to code on `localhost` or a
> private network, use **webhook-forwarding-internal**; to relay server-side to
> another public URL, use **webhook-forwarding-public**; to reshape payloads, use
> **webhook-transformations**.

## Quick start (the whole loop)

```bash
B=https://bin.webhookrelay.com

# 1. Create a bin, capture its ID
BIN=$(curl -s -X POST $B/v1/bins | jq -r .id)

# 2. The public URL to give any webhook sender (accepts ANY method):
echo "$B/v1/webhooks/$BIN"

# 3. Send a test webhook to it
curl -s -X POST "$B/v1/webhooks/$BIN" -H 'Content-Type: application/json' -d '{"hello":"world"}'

# 4. Read back every captured request (raw JSON):
curl -s "$B/v1/bins/$BIN" | jq '.requests'
```

Open the same bin in a browser UI: `https://webhookrelay.com/webhook-bin?bin=<BIN_ID>`

## Create a bin

`POST /v1/bins` (no body). Returns `201` with the bin, including its `id`:

```bash
BIN=$(curl -s -X POST $B/v1/bins | jq -r .id)
```

## The receiver URL

```
https://bin.webhookrelay.com/v1/webhooks/<BIN_ID>
```

Give this to any service. It accepts **any** method (`GET`/`POST`/`PUT`/`PATCH`/
`DELETE`/…), any headers, and any body, and records each request. It replies
with the bin's configured response (default `200`, empty body).

## Read captured webhooks

`GET /v1/bins/{id}` returns the bin plus every captured request in `requests`:

```bash
curl -s "$B/v1/bins/$BIN" | jq '.requests'
```

Each request object:

| field | meaning |
|---|---|
| `id` | request ID (sortable ULID) |
| `receivedAt` | Unix timestamp, **seconds** |
| `method` | HTTP method |
| `header` | map of `name → { key, values[] }` (array — headers can repeat) |
| `query` | raw query string (no leading `?`) |
| `body` | raw request body as a string (parse JSON yourself) |
| `ip` | sender IP |
| `responseStatus` | status the bin returned to the sender |

Common extractions:

```bash
# Most recent request's body
curl -s "$B/v1/bins/$BIN" | jq -r '.requests | sort_by(.receivedAt) | last | .body'

# How many captured so far
curl -s "$B/v1/bins/$BIN" | jq '.requests | length'

# A specific header value (case-sensitive key)
curl -s "$B/v1/bins/$BIN" | jq -r '.requests | last | .header["Content-Type"].values[0]'
```

### Wait for a webhook to arrive

Poll until at least one request lands (good for "I just triggered something"):

```bash
until [ "$(curl -s "$B/v1/bins/$BIN" | jq '.requests | length')" -gt 0 ]; do sleep 2; done
curl -s "$B/v1/bins/$BIN" | jq '.requests | last'
```

### Stream new requests live (SSE)

```bash
curl -N "$B/v1/events?stream=$BIN"
```

Each new request is pushed as an SSE `data:` line containing the request JSON.
To block for exactly **one** request and then exit:

```bash
curl -sN "$B/v1/events?stream=$BIN" | grep -m1 '^data:' | sed 's/^data: //' | jq .
```

### Only process new requests (incremental polling)

`GET` returns the *full* history each time, so track the newest `receivedAt` you
have already seen and filter client-side instead of reprocessing everything:

```bash
SEEN=0
while true; do
  # Fetch once and reuse the same response for both printing and the SEEN
  # update — two separate calls could drop a request that arrives between them.
  RESP=$(curl -s "$B/v1/bins/$BIN")
  echo "$RESP" | jq -c --argjson seen "$SEEN" '.requests | map(select(.receivedAt > $seen)) | sort_by(.receivedAt)[]'
  SEEN=$(echo "$RESP" | jq --argjson seen "$SEEN" '[.requests[].receivedAt] | max // $seen')
  sleep 3
done
```

## Mock the response the bin returns

`PUT /v1/bins/{id}` configures what the receiver replies with — handy for
simulating a real endpoint (custom status/body/headers, latency, and
intermittent failures so you can test a sender's retry logic).

```bash
curl -s -X PUT "$B/v1/bins/$BIN" -H 'Content-Type: application/json' -d '{
  "id": "'"$BIN"'",
  "response": {
    "status": 201,
    "body": "{\"ok\":true}",
    "delay": 250,
    "header": { "Content-Type": { "key": "Content-Type", "values": ["application/json"] } },
    "failures": [ { "percentage": 10, "status": 500, "body": "simulated failure" } ]
  }
}'
```

`response` fields: `status` (int), `body` (string, ≤500 KB), `delay`
(milliseconds before replying), `header` (same `{ key, values[] }` shape), and
`failures[]` — each entry has a `percentage` (0–100) chance to override the reply
with its own `status`/`body`. Set a failure to `100` to force errors every time.

## Verify a webhook signature (HMAC)

Many providers (Stripe, GitHub, Shopify, …) sign payloads with an HMAC. Compute
the expected signature and compare it to the header the provider sent:

`POST /v1/hmac` with `{ algorithm, secret, body }` where `body` is **base64**
encoded. Supported algorithms: `md5`, `sha1`, `sha256`, `sha512`. Returns
`{ "signature": "<hex>" }`.

```bash
# Verify a GitHub-style sha256 signature against the captured raw body
RAW=$(curl -s "$B/v1/bins/$BIN" | jq -r '.requests | last | .body')
# Note: pipe base64 through `tr -d '\n'` — GNU base64 wraps at 76 cols, which
# would embed newlines in the body and produce a wrong signature.
SIG=$(curl -s -X POST "$B/v1/hmac" -H 'Content-Type: application/json' -d "$(jq -nc \
  --arg s "$WEBHOOK_SECRET" --arg b "$(printf %s "$RAW" | base64 | tr -d '\n')" \
  '{algorithm:"sha256", secret:$s, body:$b}')" | jq -r .signature)

echo "expected: sha256=$SIG"
# Compare with the provider's header, e.g. X-Hub-Signature-256 captured above.
```

The returned `signature` is lowercase hex; prefix it as the provider expects
(GitHub uses `sha256=<hex>`; Stripe builds `t=…,v1=<hex>` over `"{t}.{body}"`).

## Delete a bin

```bash
curl -s -X DELETE "$B/v1/bins/$BIN"
```

## Endpoint reference

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/bins` | Create a bin |
| `GET` | `/v1/bins/{id}` | Get bin + all captured requests |
| `PUT` | `/v1/bins/{id}` | Configure the bin's response |
| `DELETE` | `/v1/bins/{id}` | Delete the bin |
| *(any)* | `/v1/webhooks/{id}` | Public receiver — send webhooks here |
| `GET` | `/v1/events?stream={id}` | SSE stream of new requests |
| `POST` | `/v1/hmac` | Compute an HMAC signature for verification |
| `GET` | `/v1/health` | Health check |

## Limits & behaviour

- Bins and requests are garbage-collected after ~48 hours.
- Public — anyone with the bin ID can read it. Never send secrets.
- Request and response bodies are capped at 500 KB.
- The service is rate limited; a bin flooded with requests is temporarily
  shielded and returns `429`.
- For **permanent** URLs, delivery to localhost/private networks, payload
  transformation, or fan-out, use the `relay` CLI and the forwarding skills.

## Verify

End-to-end smoke test (create → send → read → clean up):

```bash
B=https://bin.webhookrelay.com
BIN=$(curl -s -X POST $B/v1/bins | jq -r .id)
curl -s -o /dev/null -X POST "$B/v1/webhooks/$BIN" -d '{"smoke":"test"}'
test "$(curl -s "$B/v1/bins/$BIN" | jq '.requests | length')" -ge 1 && echo "OK: captured" || echo "FAIL"
curl -s -X DELETE "$B/v1/bins/$BIN" >/dev/null
```

See `examples/agent-recipe.sh` for a fuller "wait for one webhook then print it"
script.

## References

Plain-markdown pages (append `.md` to read directly):
- Agent/text-mode guide for the bin API: https://webhookrelay.com/webhook-bin.md
- Interactive webhook tester (UI): https://webhookrelay.com/webhook-bin
- HMAC verification background: https://webhookrelay.com/hmac-verification
- Deliver these webhooks to localhost instead: see the `webhook-forwarding-internal` skill
- Docs index: https://webhookrelay.com/llms.txt
