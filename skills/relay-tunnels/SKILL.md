---
name: relay-tunnels
description: >-
  Expose a local or internal service to the public internet over a Webhook Relay
  tunnel — get a stable public HTTPS (or TCP) hostname that forwards to
  something running on localhost or a private network, without opening firewall
  ports. Use to share a dev server, demo a local web app, expose a local API/
  webhook receiver, give a teammate or external service access to a service with
  no public IP, or tunnel TCP (SSH, databases). Triggers: "expose localhost",
  "public URL for my local server", "ngrok-style tunnel", "share my dev site",
  "tunnel to my internal service", "TCP tunnel / expose SSH". Distinct from
  webhook forwarding: a tunnel is a general-purpose reverse proxy for any
  inbound traffic; webhook forwarding (see webhook-forwarding-* skills) is
  specifically for relaying provider webhooks into a bucket.
---

# Exposing services with Webhook Relay tunnels

A **tunnel** publishes a public hostname (e.g.
`https://myapp.webrelay.io`) and routes all traffic hitting it to a destination
your machine can reach (e.g. `http://localhost:3000`). The `relay` agent keeps an
outbound connection open, so no inbound ports or public IP are required. Unlike
webhook forwarding (which delivers provider webhooks into a bucket), a tunnel
proxies **any** inbound HTTP or TCP traffic — ideal for dev servers, demos,
local APIs, and TCP services.

```
Internet ──▶ https://myapp.webrelay.io  (public tunnel host)
                       │  (over the agent's outbound connection)
                       ▼
              relay agent  ──▶  http://localhost:3000  (your service)
```

## Prerequisites

1. `relay` CLI installed: https://webhookrelay.com/docs/installation/cli
2. Logged in: `relay login`. Confirm with `relay tunnel ls`.

## Fastest path: `relay connect`

`relay connect` creates the tunnel config (if needed) and **starts the agent**,
exposing your destination immediately.

```bash
# Expose a local web app; a public *.webrelay.io host is assigned and printed.
relay connect http://localhost:3000
```

Pin a friendly name / subdomain and enable HTTPS:

```bash
relay connect --name myapp --subdomain myapp --crypto flexible \
  http://localhost:3000
# → https://myapp.webrelay.io  (reusable: same name keeps the same host)
```

The agent runs in the foreground and logs each request. Ctrl-C to stop; re-run
the same command to bring it back on the same hostname.

### Common flags (`relay connect`)
- `--name, -n` — tunnel name (stable identity; reuse to keep the same host).
- `--subdomain, -s` / `--host, -H` — preferred subdomain or full custom host.
- `--crypto, -c` — TLS mode: `flexible` (HTTPS at the edge, HTTP to your
  service — most common), `full`, `full-strict`, or `tls-pass-through`.
- `--region, -r` — pick a region (e.g. `eu`, `us-west`) to lower latency.
- `--username, -u` / `--password, -p` — protect the tunnel with HTTP basic auth.
- `--rewrite-host-header` — set the Host header sent to your service (needed by
  many vhost-based apps and dev servers).
- `--protocol` — `http` (default) or `tcp` (expose SSH, databases, etc.).
- `--group, -g` — group tunnels so one agent can serve several at once.
- `--no-agent` — only create the configuration, don't start the agent.

## Explicit, persistent setup

Create the tunnel once, then run the agent whenever (foreground or as a service).

```bash
# 1. Create the tunnel definition
relay tunnel create myapp \
  --destination http://localhost:3000 \
  --subdomain myapp --crypto flexible --region eu

# 2. Inspect / list
relay tunnel ls
relay tunnel inspect myapp

# 3. Start the agent to serve it
relay connect --name myapp            # foreground
#   …or run relay as a background OS service:
relay service install
relay service start
```

Update or remove later:
```bash
relay tunnel update myapp --rewrite-host-header localhost
relay tunnel rm myapp
```

## Recipes

**Share a dev server with the right Host header**
```bash
relay connect -n dev -s dev -c flexible --rewrite-host-header localhost \
  http://localhost:5173
```

**Password-protect a demo**
```bash
relay connect -n demo -s demo -c flexible -u alice -p s3cret \
  http://localhost:8080
```

**Expose a service on a private LAN host (run the agent on a machine that can
reach it)**
```bash
relay connect -n grafana -s grafana -c flexible http://10.0.0.5:3000
```

**TCP tunnel (e.g. SSH)**
```bash
relay tunnel create ssh-box --protocol tcp --destination tcp://localhost:22
relay connect --name ssh-box
```

## Verify
Open the printed `https://<host>` in a browser (or `curl` it). Requests appear
in the agent's terminal log. If you see a connection error, confirm the local
service is up and that `--rewrite-host-header` matches what your app expects.

## Tunnel vs. webhook forwarding — which do I want?
- **Tunnel** (this skill): a public host that proxies *all* inbound HTTP/TCP
  traffic to a local/internal service. For dev servers, demos, APIs, SSH.
- **Webhook forwarding** (`webhook-forwarding-internal` / `-public`): a
  bucket-based pipeline purpose-built for relaying provider webhooks, with
  inputs/outputs, fan-out, retries, and transformation functions.
