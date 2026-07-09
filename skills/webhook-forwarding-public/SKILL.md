---
name: webhook-forwarding-public
description: >-
  Receive webhooks on a public Webhook Relay endpoint and forward them
  server-side to another publicly reachable URL — no local agent required.
  Use this to relay, fan-out, proxy, or transform webhooks between cloud
  services: e.g. point a provider at a stable Webhook Relay URL and have it
  deliver to one or more SaaS/API endpoints (Slack, Discord, an internal API
  gateway, another webhook host). Triggers: "forward webhooks to a public URL",
  "relay between two cloud services", "fan out a webhook to several endpoints",
  "add a stable webhook URL in front of my API", "send a webhook to Slack/
  Discord without running anything". For delivering to localhost or a private
  network, use webhook-forwarding-internal instead.
---

# Forwarding webhooks to public destinations

A **public** output is delivered by Webhook Relay's servers directly to a
destination that is already reachable on the internet. Unlike an internal
output, **no `relay` agent needs to run** — once configured it works 24/7.

```
Provider ──POST──▶ https://my.webhookrelay.com/v1/webhooks/<id>  (input)
                              │  (delivered server-side, no agent)
                              ▼
                   https://hooks.slack.com/services/…   (public output)
```

Use this when both ends live on the internet: putting a stable, provider-facing
URL in front of an API, relaying between SaaS products, fanning one webhook out
to many destinations, or applying a transformation in transit.

## Tooling preference

Use the Webhook Relay MCP server first when it is connected. Public forwarding
is pure account configuration, so MCP can usually do the whole job:
- create/list buckets and inputs
- create/list outputs
- attach transform functions during bucket/output creation
- set routing rules
- inspect webhook logs

Use the `relay` CLI only when MCP is not connected but the CLI is authenticated
and working, or when you need a CLI-only capability.

## MCP-first setup

Create the bucket, public input, and public output with MCP:

1. If a transform is needed, use the `webhook-transformations` skill first:
   create the function, execute it with representative payloads, and keep the
   function ID.
2. Call `create_bucket`:
   - `name`: stable bucket name, e.g. `to-slack`
   - `destination`: internet-reachable URL, e.g.
     `https://hooks.slack.com/services/T000/B000/XXXX`
   - `internal`: `false`
   - `output_function_id`: optional transform function ID
3. Return the `endpoint_url` from the created input to the user; this is the URL
   the provider should call.

Use MCP `list_buckets`, `list_webhook_logs`, and `get_webhook_log` to inspect
the configuration and delivery state.

## CLI fallback

If MCP is not available but the CLI is authenticated, `relay forward --type
public` can create the same configuration:

```bash
relay forward --type public --bucket to-slack \
  https://hooks.slack.com/services/T000/B000/XXXX
```

- Creates the bucket, a public input, and a **public** output.
- Prints the public input URL (e.g.
  `https://my.webhookrelay.com/v1/webhooks/2a1b…`) — hand this to the provider.
- Because the output is public, the CLI configures and exits; it does **not**
  subscribe to a stream or keep an agent running. Delivery happens on Webhook
  Relay's side.

> With `--type public` the agent is not needed, so you can run the command from
> anywhere (CI, a one-off shell) and forget about it.

For explicit CLI setup:

```bash
# 1. Bucket
relay bucket create to-slack

# 2. Public input (the URL you give to the provider)
relay input create --bucket to-slack "incoming"

# 3. Public output (the internet-reachable destination). The first positional
#    arg ("slack") is the output NAME — always give one (see note below).
relay output create slack --bucket to-slack --type public \
  --destination https://hooks.slack.com/services/T000/B000/XXXX
```

> **Name every output.** The output name is the first positional argument. If
> you omit it the output gets an empty name, and adding a second un-named output
> to the same bucket fails with `output with name '' already exists` — which
> breaks fan-out. Give each output a distinct name.

Inspect with MCP when available, or CLI fallback:

```bash
relay input ls            # shows the public endpoint to share
relay output ls
relay bucket inspect to-slack
```

## Common patterns

**Fan-out — one webhook to many destinations.** Add several outputs to the same
bucket; every received webhook is delivered to all of them.

With MCP, create additional public outputs on the bucket. CLI fallback:

```bash
relay output create slack   -b alerts --type public -d https://hooks.slack.com/services/…
relay output create discord -b alerts --type public -d https://discord.com/api/webhooks/…
relay output create ingest  -b alerts --type public -d https://example.com/ingest
```

**Transform in transit.** Most public destinations expect a specific JSON shape
(Slack/Discord/Teams). Attach a JavaScript function to the output to reshape the
payload — see the `webhook-transformations` skill. Prefer MCP `create_function`,
`execute`, and `create_bucket`/`attach_function`. CLI fallback:

```bash
relay output create slack -b to-slack --type public \
  -d https://hooks.slack.com/services/… \
  --function to-slack-message
# or attach during CLI fallback creation:
relay forward --type public -b to-slack -f to-slack-message \
  https://hooks.slack.com/services/…
```

**Override request headers** (e.g. inject auth for the destination):

Prefer MCP output configuration when available. CLI fallback:

```bash
relay output create api -b to-api --type public -d https://api.example.com/ingest \
  --header "Authorization=Bearer XXX" --header "Content-Type=application/json"
```

**Custom response to the caller.** Configure the input to return a specific
status/body, or echo a downstream response, when the provider requires a
particular acknowledgement:

Prefer MCP input configuration when available. CLI fallback:

```bash
relay input create -b to-api "incoming" \
  --status-code 200 --response-body 'ok'
```

## Verify

```bash
curl -X POST https://my.webhookrelay.com/v1/webhooks/<id> \
  -H 'Content-Type: application/json' -d '{"text":"hello from relay"}'
```
Check the destination received it. Use the Webhook Relay dashboard logs, or
MCP `list_webhook_logs` / `get_webhook_log`, or point a test output at
https://bin.webhookrelay.com / https://webhook.site to inspect exactly what gets
delivered.

## internal vs public — pick the right output type

| | internal | public |
|---|---|---|
| Destination | localhost / private network | internet-reachable URL |
| Agent required | **yes**, must be running | **no**, delivered server-side |
| Skill | `webhook-forwarding-internal` | this one |

A single bucket can mix both: e.g. deliver to a public Slack webhook *and* to a
local dev server at the same time.

## References

Webhook Relay docs (these `.md` URLs render as plain markdown for easy reading):
- Forward to a public URL: https://webhookrelay.com/docs/webhooks/public/public-destination.md
- Multiple destinations: https://webhookrelay.com/docs/webhooks/public/multiple-destination-urls.md — feature overview: https://webhookrelay.com/features/webhook-multiple-destinations.md
- Filter & route with forwarding rules: https://webhookrelay.com/features/forwarding-rules.md
- Custom subdomains: https://webhookrelay.com/docs/webhooks/custom-subdomains.md — custom domains: https://webhookrelay.com/docs/webhooks/custom-domains.md
- Transform in transit with functions: https://webhookrelay.com/docs/webhooks/functions.md
- Install the CLI: https://webhookrelay.com/docs/installation/cli.md
