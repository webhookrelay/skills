# Webhook Relay Skills

Agent [Skills](https://agentskills.io/specification) that teach Claude (and other
skill-aware agents) how to drive [Webhook Relay](https://webhookrelay.com) with
the `relay` CLI and API — forwarding webhooks, transforming them, exposing
services over tunnels, and scheduling recurring webhooks.

## Skills

| Skill | What it does |
|---|---|
| [`webhook-forwarding-internal`](skills/webhook-forwarding-internal) | Receive webhooks on a public endpoint and forward them to localhost / a private network (agent required). |
| [`webhook-forwarding-public`](skills/webhook-forwarding-public) | Forward webhooks server-side to a public URL, fan out to many destinations (no agent). |
| [`webhook-transformations`](skills/webhook-transformations) | Write, test, and attach JavaScript (or Lua) functions that reshape webhooks in flight. |
| [`relay-tunnels`](skills/relay-tunnels) | Expose a local/internal HTTP or TCP service on a public hostname. |
| [`recurring-webhooks`](skills/recurring-webhooks) | Schedule cron-driven webhooks (interval or specific times/timezone). |

## Install

With the [skills CLI](https://www.skills.sh):

```bash
npx skills add webhookrelay/skills
```

Or as a Claude Code plugin marketplace (see `.claude-plugin/marketplace.json`),
or by copying any `skills/<name>/` folder into your agent's skills directory.

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
