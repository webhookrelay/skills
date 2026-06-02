---
name: webhook-forwarding-internal
description: >-
  Receive webhooks from external providers (Stripe, GitHub, Shopify, Slack,
  CI systems, etc.) and forward them to a destination running behind a firewall
  or on localhost that has no public IP — using Webhook Relay's `relay` CLI.
  Use this when the user wants to test or run a webhook handler locally
  (localhost, 127.0.0.1, a private LAN host, or a Kubernetes service) and have a
  third party POST to it. Triggers: "receive webhooks locally", "test my Stripe/
  GitHub webhook on localhost", "forward webhooks to my internal service",
  "webhook tunnel for development", "no public IP for my webhook endpoint".
  For forwarding to an already-public URL instead, use webhook-forwarding-public.
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

## Prerequisites

1. The `relay` CLI installed: https://webhookrelay.com/docs/installation/cli
2. Logged in: `relay login` (or set `RELAY_KEY` / `RELAY_SECRET`). Confirm with
   `relay bucket ls`.

## Fastest path: `relay forward`

`relay forward` creates a bucket + public input + internal output and then
**starts the agent and subscribes to the stream** in one command. This is the
right tool for local development.

```bash
# Forward everything sent to a new public endpoint to a local server.
relay forward --bucket my-app http://localhost:8080/webhook
```

What happens:
- A bucket named `my-app` is created (if it doesn't exist).
- A public input endpoint is printed, e.g.
  `https://my.webhookrelay.com/v1/webhooks/2a1b…` — **give this URL to the
  provider** (Stripe dashboard, GitHub webhook settings, etc.).
- The agent stays in the foreground; every received webhook is forwarded to
  `http://localhost:8080/webhook` and the request/response are logged to your
  terminal.

Stop with Ctrl-C. Restart later with the **same** command, or just re-attach the
agent to the existing bucket:

```bash
relay forward --bucket my-app          # no destination → relays all configured
                                       # outputs in the bucket
```

`--type internal` is the default, so you don't need to pass it.

### Useful flags
- `--bucket, -b` — bucket name (defaults to the destination host). Reuse the
  same name to keep one stable public URL across restarts.
- `--function, -f <name|id>` — attach a JavaScript/Lua transformation to the
  output (see the `webhook-transformations` skill).
- `--no-agent` — only create the configuration, do not start streaming.
- `--max-retries`, `--retry-wait-min`, `--retry-wait-max` — retry behaviour when
  the destination returns `>= 500`.

## Verify it works

In one terminal start a throwaway server, in another run the agent, then send a
test request to the **public input URL** (not to localhost):

```bash
# terminal 1 – a server that prints what it receives
python3 -m http.server 8080

# terminal 2 – forward to it
relay forward -b my-app http://localhost:8080

# terminal 3 – simulate a provider hitting the public endpoint
curl -X POST https://my.webhookrelay.com/v1/webhooks/<id> -d '{"hello":"world"}'
```

You should see the request logged by the agent and delivered to the local
server. https://webhook.site or https://bin.webhookrelay.com are handy for
inspecting payloads while wiring up a real provider.

## Persistent / explicit setup (CI, servers, scripting)

When you want the configuration to exist independently of an interactive
session (e.g. on a server, or managed by config-as-code), create the pieces
explicitly and run the agent as a service.

```bash
# 1. Create the bucket
relay bucket create my-app

# 2. Create the public input (receives webhooks). Prints the endpoint URL.
relay input create --bucket my-app "default public endpoint"

# 3. Create the internal output (where requests are relayed). Default type is
#    internal, so the agent must be running for delivery to happen.
relay output create --bucket my-app --destination http://localhost:8080/webhook

# 4. Run the agent so it streams the bucket to the destination
relay forward -b my-app            # foreground
# or run it as a background OS service:
relay service install
relay service start
```

Inspect anytime:
```bash
relay bucket ls
relay bucket inspect my-app
relay output ls
relay input ls          # shows the public endpoint URLs
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
- If deliveries fail, check `relay bucket inspect <name>`, confirm the local
  server is up, and watch the agent's terminal logs.
- For Kubernetes ingress (exposing in-cluster services), see `relay ingress`.

## References

Webhook Relay docs (these `.md` URLs render as plain markdown for easy reading):
- Receiving webhooks on localhost / private networks: https://webhookrelay.com/docs/webhooks/internal/localhost.md
- Webhooks to internal servers (overview): https://webhookrelay.com/features/webhook-to-internal-server.md
- Filter & route with forwarding rules: https://webhookrelay.com/features/forwarding-rules.md
- Custom subdomains: https://webhookrelay.com/docs/webhooks/custom-subdomains.md — custom domains: https://webhookrelay.com/docs/webhooks/custom-domains.md
- Transform in transit with functions: https://webhookrelay.com/docs/webhooks/functions.md
- Install the CLI: https://webhookrelay.com/docs/installation/cli.md
