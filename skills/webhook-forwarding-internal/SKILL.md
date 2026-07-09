---
name: webhook-forwarding-internal
description: >-
  Receive webhooks from external providers (Stripe, GitHub, Shopify, Slack,
  CI systems, etc.) and forward them to a destination running behind a firewall
  or on localhost that has no public IP. Configure buckets/inputs/outputs with
  Webhook Relay MCP tools when available, then use the `relay` CLI only to run
  the local forwarding agent. Use this when the user wants to test or run a
  webhook handler locally (localhost, 127.0.0.1, a private LAN host, or a
  Kubernetes service) and have a third party POST to it. Triggers: "receive
  webhooks locally", "test my Stripe/ GitHub webhook on localhost", "forward
  webhooks to my internal service", "webhook tunnel for development", "no
  public IP for my webhook endpoint". For forwarding to an already-public URL
  instead, use webhook-forwarding-public.
---

# Forwarding webhooks to internal / private destinations

Webhook Relay gives you a **public HTTPS endpoint** (an *input*) that any
provider can POST to. The `relay` agent holds an **outbound** connection to
Webhook Relay and streams each received request to a destination that only
*your* machine/network can reach (an *output*). Nothing inbound needs to be
opened on your firewall.

```
Provider ──POST──▶ https://my.webhookrelay.com/v1/webhooks/<id>  (input, public)
                              │  (Webhook Relay streams it down the agent's
                              ▼   existing outbound connection)
                   relay agent on your machine
                              │
                              ▼
                   http://localhost:8080/webhook   (output, internal)
```

Key idea: an **internal** output requires the `relay` agent to be **running**,
because it is the agent that performs the final hop to the private destination.

## Tooling preference

Use the Webhook Relay MCP server first for durable configuration when it is
connected:
- create/list buckets and inputs
- create/list outputs
- create/test/attach transform functions
- inspect webhook logs and delivery state

Use the `relay` CLI for the part MCP cannot do: running the local agent that can
reach `localhost` or a private network. If MCP is not connected but the CLI is
authenticated and working, the CLI can also create the configuration as a
fallback.

Before falling back to CLI-created config, confirm there is no usable MCP path.
If both are used, make sure they target the same Webhook Relay account.

## Prerequisites

For the runtime agent:

1. The `relay` CLI installed: https://webhookrelay.com/docs/installation/cli
2. Logged in: `relay login` (or set `RELAY_KEY` / `RELAY_SECRET`). Confirm with
   `relay bucket ls`.

## MCP-first setup

Create the Webhook Relay configuration with MCP tools:

1. If a transform is needed, create it with `create_function`, test it with
   `execute`, and keep the function ID.
2. Create the bucket with `create_bucket`:
   - `name`: stable bucket name, e.g. `my-app`
   - `destination`: private destination, e.g. `http://localhost:8080/webhook`
   - `internal`: `true`
   - `output_function_id`: optional transform function ID
3. Save the returned input `endpoint_url`; this is the public URL to give to the
   provider.

Then start the agent against that existing bucket:

```bash
relay forward --bucket my-app
```

Stop with Ctrl-C. Restart later with the **same** command, or just re-attach the
agent to the existing bucket:

```bash
relay forward --bucket my-app          # no destination → relays all configured
                                       # outputs in the bucket
```

`--type internal` is the default, so you don't need to pass it.

Avoid running `relay forward --bucket my-app http://localhost:8080/webhook`
after MCP has already created the output unless you intentionally want the CLI
to create or update configuration. The no-destination form keeps the CLI scoped
to runtime forwarding.

### Useful flags
- `--bucket, -b` — bucket name (defaults to the destination host). Reuse the
  same name to keep one stable public URL across restarts.
- `--max-retries`, `--retry-wait-min`, `--retry-wait-max` — retry behaviour when
  the destination returns `>= 500`.

## Verify it works

In one terminal start a throwaway server, in another run the agent, then send a
test request to the **public input URL** (not to localhost):

```bash
# terminal 1 – a server that prints what it receives
python3 -m http.server 8080

# terminal 2 – run the agent for the MCP-created bucket
relay forward -b my-app

# terminal 3 – simulate a provider hitting the public endpoint
curl -X POST https://my.webhookrelay.com/v1/webhooks/<id> -d '{"hello":"world"}'
```

You should see the request logged by the agent and delivered to the local
server. Use MCP `list_webhook_logs` / `get_webhook_log` to inspect delivery
state. https://webhook.site or https://bin.webhookrelay.com are handy for
inspecting payloads while wiring up a real provider.

## CLI-only fallback

If MCP is not connected but the `relay` CLI is authenticated and working, the
CLI can create the configuration and start the agent:

```bash
relay forward --bucket my-app http://localhost:8080/webhook
```

This creates the bucket, public input, and internal output, then starts the
agent in the foreground. The printed public endpoint is the URL to give to the
provider.

For explicit CLI setup:

```bash
# 1. Create the bucket
relay bucket create my-app

# 2. Create the public input (receives webhooks). Prints the endpoint URL.
relay input create --bucket my-app "default public endpoint"

# 3. Create the internal output (where requests are relayed). The first
#    positional arg is the output NAME — always give one. Default type is
#    internal, so the agent must be running for delivery to happen.
relay output create local-app --bucket my-app --destination http://localhost:8080/webhook

# 4. Run the agent so it streams the bucket to the destination
relay forward -b my-app            # foreground
# or run it as a background OS service:
relay service install
relay service start
```

> **Name your outputs.** The output name is the first positional argument
> (`local-app` above). If you omit it, the output is created with an empty name,
> and creating a second un-named output in the same bucket fails with
> `output with name '' already exists` — so naming matters as soon as you add a
> second destination.

Inspect anytime:
```bash
relay bucket ls                  # CLI fallback inspection
relay bucket inspect my-app
# Prefer MCP list_buckets / get_input / list_webhook_logs when MCP is connected.
```

Remove the whole thing when done (`-f` also removes the bucket's inputs/outputs;
without it, removing a non-empty bucket fails):
```bash
relay bucket rm my-app -f
```

## Choosing internal vs public

- **internal** (this skill): the destination is private; the **agent must be
  running** to deliver. Best for localhost, LAN hosts, dev laptops, and
  services with no public IP.
- **public**: the destination is already reachable on the internet; Webhook
  Relay delivers server-side and **no agent is needed**. Use the
  `webhook-forwarding-public` skill.

## Notes & gotchas
- Give providers the **input endpoint URL**, never `localhost`.
- One bucket can have many outputs → the same webhook fans out to several
  internal destinations.
- If deliveries fail, inspect the bucket/logs with MCP when available, confirm
  the local server is up, and watch the agent's terminal logs.
- For Kubernetes ingress (exposing in-cluster services), see `relay ingress`.

## References

Webhook Relay docs (these `.md` URLs render as plain markdown for easy reading):
- Receiving webhooks on localhost / private networks: https://webhookrelay.com/docs/webhooks/internal/localhost.md
- Webhooks to internal servers (overview): https://webhookrelay.com/features/webhook-to-internal-server.md
- Filter & route with forwarding rules: https://webhookrelay.com/features/forwarding-rules.md
- Custom subdomains: https://webhookrelay.com/docs/webhooks/custom-subdomains.md — custom domains: https://webhookrelay.com/docs/webhooks/custom-domains.md
- Transform in transit with functions: https://webhookrelay.com/docs/webhooks/functions.md
- Install the CLI: https://webhookrelay.com/docs/installation/cli.md
