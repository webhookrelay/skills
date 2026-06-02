---
name: recurring-webhooks
description: >-
  Schedule webhooks to fire automatically on a cron schedule with Webhook Relay
  — send a recurring HTTP request (with method, body, and headers) to one or
  more destinations at a fixed interval or specific times/timezone. Use for
  periodic health checks, heartbeats, scheduled reports, polling/kicking off a
  job, cron-driven Slack/Discord reminders, or triggering a transformation
  Function on a timer. Triggers: "send a webhook every X minutes/hours/day",
  "schedule a recurring webhook", "cron job that POSTs to a URL", "periodic
  health check / heartbeat", "fire a webhook at 9am daily". Managed via the
  Webhook Relay cron API (the `relay api` command) or the dashboard at
  https://my.webhookrelay.com/cron.
---

# Recurring (cron) webhooks

A **cron** in Webhook Relay sends a webhook on a schedule. Each cron has its own
bucket; the configured `payload`/`headers`/`method` are injected and delivered
to the `destination` (and to any additional outputs on its bucket) every time
the schedule fires. Failed runs are retried and visible in the dashboard.

Manage crons with the **`relay cron`** subcommand (create/ls/inspect/update/rm),
the REST API via `relay api`, or the dashboard at
https://my.webhookrelay.com/cron.

> Requires a `relay` CLI build that includes the `cron` command. If
> `relay cron --help` is not found, update the CLI or use the `relay api` path
> shown further below — both hit the same `/v1/crons` API.

## Prerequisites

1. `relay` CLI installed and logged in (`relay login`). Confirm with
   `relay cron ls` (or `relay api /v1/crons --jq '.'`).

## Cron object fields

| field | type | notes |
|---|---|---|
| `name` | string | display name |
| `enabled` | bool | set `true` to activate |
| `recurring` | bool | `true` for a repeating schedule |
| `schedule` | string | 5-field cron expression, e.g. `*/15 * * * *` |
| `timezone` | string | IANA tz, e.g. `Europe/London`, `America/New_York` |
| `method` | string | `GET`, `POST`, … |
| `destination` | string | URL the webhook is sent to |
| `payload` | string | request body (JSON should be a **string**) |
| `headers` | object | `{"Header-Name": "value"}` |
| `function_id` | string | optional: transform the request (see webhook-transformations) |
| `starts_at` / `ends_at` | RFC3339 | optional active window |

**Schedule format** is standard 5-field cron (`minute hour day month weekday`):
- `*/15 * * * *` — every 15 minutes
- `0 * * * *` — hourly, on the hour
- `0 9 * * *` — every day at 09:00 (in the cron's `timezone`)
- `0 9 * * 1-5` — 09:00 on weekdays
- `0 0 1 * *` — 00:00 on the 1st of each month

## Create and manage with `relay cron`

```bash
# Create (prints the new cron ID). --schedule and --destination are required.
relay cron create hourly-ping \
  --schedule "0 * * * *" \
  --timezone "Europe/London" \
  --method POST \
  --destination https://example.com/webhook \
  --payload '{"ping":"hourly"}' \
  --header Content-Type=application/json

# List (table shows SCHEDULE, TIMEZONE, METHOD, DESTINATION, ENABLED, NEXT RUN)
relay cron ls

# Inspect full JSON (by name or ID)
relay cron inspect hourly-ping

# Update only the fields you pass (others are preserved)
relay cron update hourly-ping --schedule "*/30 * * * *"
relay cron update hourly-ping --enabled=false      # pause without deleting
relay cron update hourly-ping --function format-payload   # attach a transform

# Remove
relay cron rm hourly-ping
```

Key `create`/`update` flags: `--schedule/-s`, `--timezone`, `--method/-m`
(default `POST`), `--destination/-d`, `--payload/-p`, `--header` (repeatable
`key=value`), `--function/-F` (name or ID), `--enabled`, `--recurring`.

## Alternative: the raw REST API (`relay api`)

Works on any CLI version and is handy for scripting from a JSON file. See
`examples/cron.json`.

```bash
# Create
relay api -X POST /v1/crons --input examples/cron.json --jq '.id'

# Create inline (-F = typed bool/number, -f = string)
relay api -X POST /v1/crons \
  -f name="hourly-ping" -F enabled=true -F recurring=true \
  -f schedule="0 * * * *" -f timezone="Europe/London" \
  -f method="POST" -f destination="https://example.com/webhook" \
  -f payload='{"ping":"hourly"}'

# List / get / update / delete
relay api /v1/crons --jq '.'
relay api /v1/crons/<id> --jq '.'
relay api -X PUT /v1/crons/<id> --input examples/cron.json
relay api -X DELETE /v1/crons/<id> -i        # expect: HTTP/1.1 204 No Content
```

## Patterns

**Fan-out on a schedule.** A cron delivers to its `destination`; to hit several
endpoints, add extra outputs to the cron's bucket (`relay output ls` /
`relay output create -b <bucket> --type public -d <url>`).

**Transform on a timer.** Set `function_id` to a deployed JavaScript function to
build/sign the payload at send time (e.g. format a Slack reminder). See the
`webhook-transformations` skill.

**Health checks / heartbeats.** Point `destination` at a monitoring endpoint
(e.g. a Better Uptime / Healthchecks.io ping URL) on a tight schedule like
`*/5 * * * *`.

## Verify
After creating, list crons and check `next_run`. Point `destination` at
https://bin.webhookrelay.com or https://webhook.site first to watch the
scheduled requests arrive, then switch to the real target. The dashboard
(https://my.webhookrelay.com/cron) shows run history and lets you retry failures.

## Notes
- Times are interpreted in the cron's `timezone`; set it explicitly to avoid UTC
  surprises.
- `payload` is a string — JSON-encode objects (e.g. `"{\"ping\":\"hourly\"}"`).
- Set `enabled: false` to pause without deleting.
