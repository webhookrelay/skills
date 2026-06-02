# Webhook Relay Skills

Agent [Skills](https://agentskills.io/specification) that teach Claude (and other
skill-aware agents) how to drive [Webhook Relay](https://webhookrelay.com) with
the `relay` CLI and API — forwarding webhooks, transforming them, exposing
services over tunnels, and scheduling recurring webhooks.

## Install all skills

With the [skills CLI](https://www.skills.sh):

```bash
npx skills add webhookrelay/skills
```

Add `-g` to install globally for all your agents. You can also use this repo as a
Claude Code plugin marketplace (see `.claude-plugin/marketplace.json`), or copy
any `skills/<name>/` folder into your agent's skills directory. To install just
one skill, use the `--skill <name>` command shown in each section below.

## Skills

### `webhook-forwarding-internal`

Receive webhooks from external providers (Stripe, GitHub, Shopify, CI systems,
etc.) on a public Webhook Relay endpoint and forward them to a destination that
has no public IP — `localhost`, a private LAN host, or a Kubernetes service. The
`relay` agent holds the outbound connection and performs the final hop, so no
inbound firewall ports are needed. Best for local development and testing
provider webhooks against code running on your machine.

```bash
npx skills add webhookrelay/skills --skill webhook-forwarding-internal
```

### `webhook-forwarding-public`

Forward webhooks server-side from a public Webhook Relay endpoint to another
internet-reachable URL — no local agent required. Use it to relay between cloud
services, put a stable URL in front of an API, fan one webhook out to many
destinations, or transform payloads in transit (e.g. into Slack/Discord format).

```bash
npx skills add webhookrelay/skills --skill webhook-forwarding-public
```

### `webhook-transformations`

Write, test, and attach JavaScript (or Lua) functions that modify webhooks in
flight — reshape the JSON body, rename/format fields, add/remove headers, change
the method or path, set the response, drop requests conditionally, or call other
HTTP APIs. Covers the function API, local testing with `relay function test`,
and attaching functions to inputs/outputs.

```bash
npx skills add webhookrelay/skills --skill webhook-transformations
```

### `relay-tunnels`

Expose a local or internal HTTP/TCP service on a stable public hostname (an
ngrok-style reverse proxy) without opening firewall ports — share a dev server,
demo a local web app, expose an internal API, or tunnel TCP (SSH, databases).
Covers TLS modes, regions, basic auth, host-header rewriting, and running the
agent as a service.

```bash
npx skills add webhookrelay/skills --skill relay-tunnels
```

### `recurring-webhooks`

Schedule cron-driven webhooks that fire automatically — send a recurring HTTP
request (method, body, headers) to one or more destinations on an interval or at
specific times/timezone. Use for health checks, heartbeats, scheduled reports,
or triggering a transformation function on a timer. Managed via the `relay cron`
command or the `/v1/crons` API.

```bash
npx skills add webhookrelay/skills --skill recurring-webhooks
```

## Prerequisites

All skills use the `relay` CLI:

1. Install it: https://webhookrelay.com/docs/installation/cli
2. Log in: `relay login` (or set `RELAY_KEY` / `RELAY_SECRET`).
3. Verify: `relay bucket ls`.

## Concepts at a glance

- **Bucket** — groups inputs and outputs.
- **Input** — a public HTTPS endpoint that receives webhooks.
- **Output** — a destination requests are relayed to; `internal` (delivered by a
  running agent, e.g. localhost) or `public` (delivered server-side).
- **Function** — server-side JavaScript/Lua that transforms requests/responses.
- **Tunnel** — a public hostname that proxies inbound HTTP/TCP to a local/
  internal service.
- **Cron** — a scheduled, recurring webhook.

## Links

- Docs: https://webhookrelay.com/docs
- Functions reference: https://webhookrelay.com/docs/webhooks/functions
- Cron webhooks: https://webhookrelay.com/cron
- Dashboard: https://my.webhookrelay.com
- LLM-friendly docs index (append `.md` to any docs URL for plain markdown): https://webhookrelay.com/llms.txt

Each skill's **References** section links the relevant docs as `.md` URLs that
render as plain markdown — handy for agents to fetch and read directly.
