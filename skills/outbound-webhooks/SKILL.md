---
name: outbound-webhooks
description: >-
  Send webhooks from your product to your customers with Webhook Relay's
  Outbound Gateway (webhooks as a service): define event types, register each
  customer as a consumer with their HTTPS endpoints, publish an event once and
  let Webhook Relay deliver signed Standard Webhooks with retries, per-endpoint
  rate limits, health tracking and 35 days of delivery history. Also covers
  inspecting deliveries, retrying/recovering/replaying failures, rotating
  signing secrets, and migrating from Svix, Hookdeck Outpost, Convoy, Hook0 or a
  home-grown sender while keeping customers' existing signing secrets.
  Triggers: "send webhooks to my customers", "add webhooks to my SaaS/API",
  "webhooks as a service", "Svix alternative", "migrate from Svix/Hookdeck
  Outpost/Convoy/Hook0", "publish an event to customer endpoints", "why did a
  customer's webhook fail", "replay failed webhooks". For relaying webhooks you
  RECEIVE from providers, use webhook-forwarding-public / -internal instead.
---

# Outbound webhooks (send webhooks to your customers)

Use this when a **producer** (your product) sends events to **its own
customers**. Webhook Relay accepts each event once, fans it out to every
subscribed endpoint of that customer, signs it with
[Standard Webhooks](https://www.standardwebhooks.com/) and retries failures.
For webhooks your app *receives* from Stripe, GitHub, etc., use the forwarding
skills instead.

Vocabulary:

- **Consumer**: one of your customers. You pick its ID (e.g. your tenant ID).
- **Event type**: an entry in your catalog, e.g. `invoice.paid`.
- **Endpoint**: a consumer's public HTTPS URL subscribed to event types, with
  its own signing secret, rate limit and health.
- **Message**: one published event, delivered to every endpoint of its consumer
  that subscribes to its event type.

## Access and plans

The Outbound Gateway is included on the Basic, Business and Pro plans (not
Free). Check access and effective limits first:

- MCP: `get_outbound_access`
- REST: `GET https://my.webhookrelay.com/v1/outbound/access`

`enabled: false` means the account is on the Free plan: ask the user to upgrade
to Basic or above (plans: https://webhookrelay.com/pricing/) before continuing.

| Plan | Customers (consumers) | Endpoints per customer | Event types |
|---|---|---|---|
| Basic | 100 | 10 | 300 |
| Business | 500 | 25 | 500 |
| Pro | 1,000 | 100 | 1,000 |

No per-message fees; retries and fan-out are free, and outbound messages don't
count against the inbound webhook quota. Payloads are JSON up to 256 KiB.

## Tooling preference

1. **MCP first** (Webhook Relay MCP server connected): every operation below has
   a tool with the same name.
2. **Code** (adding webhooks to the user's app): use the SDKs. TypeScript
   [`@webhookrelay/sdk`](https://www.npmjs.com/package/@webhookrelay/sdk)
   (`relay.outbound.consumers`, `.eventTypes`, `.endpoints`, `.messages`,
   `.recoveryTasks`) and Go
   [`github.com/webhookrelay/webhookrelay-go`](https://github.com/webhookrelay/webhookrelay-go)
   (`api.UpsertOutboundConsumer`, `api.CreateOutboundEndpoint`,
   `api.PublishOutboundMessage`, ...). Both read `RELAY_API_KEY`.
3. **REST** under `https://my.webhookrelay.com/v1/outbound` (`consumers`,
   `event-types`, `endpoints`, `messages`, `recovery-tasks`) with
   `Authorization: Bearer $RELAY_API_KEY`.

For production code, create an API token restricted to outbound
(`permissions.outbound`: `read`, `publish` or `manage`). Such tokens reach only
`/v1/outbound/*`. Never put a producer token in browser or customer-facing code.

## Onboarding (MCP tool calls)

1. `save_outbound_event_type`: `{ "name": "invoice.paid", "description": "An invoice was paid" }`
2. `upsert_outbound_consumer`: `{ "id": "customer_42", "name": "Acme" }`
3. `create_outbound_endpoint`:
   `{ "consumer": "customer_42", "url": "https://customer.example/webhooks", "event_types": ["invoice.paid"] }`
4. `publish_outbound_message`:
   `{ "consumer": "customer_42", "event_type": "invoice.paid", "idempotency_key": "invoice-paid:inv_123", "payload": { "invoice_id": "inv_123", "amount": 4900 } }`

The same flow in TypeScript:

```ts
import { WebhookRelay } from "@webhookrelay/sdk";

const relay = new WebhookRelay(); // reads RELAY_API_KEY

await relay.outbound.eventTypes.upsert("invoice.paid", { description: "An invoice was paid" });
await relay.outbound.consumers.upsert("customer_42", { name: "Acme" });
const endpoint = await relay.outbound.endpoints.create("customer_42", {
  url: "https://customer.example/webhooks",
  eventTypes: ["invoice.paid"],
});
// endpoint.secret is sensitive: show it to the customer once, never log it.

await relay.outbound.messages.publish(
  { consumer: "customer_42", eventType: "invoice.paid", payload: { invoice_id: "inv_123", amount: 4900 } },
  { idempotencyKey: "invoice-paid:inv_123" },
);
```

The customer supplies the destination URL. Endpoints must be public HTTPS;
private networks, redirects, URL credentials and `webhook-*` header overrides
are rejected. A deleted consumer's ID cannot be reused.

## Publishing

Publishing returns a durable receipt (`202`): the message ID and the endpoints
it will go to. Reusing an idempotency key with the same message returns the
same receipt; a different message under the same key is a conflict. A message
with no subscribed endpoints is still accepted, and endpoints added later do
not receive it.

`get_outbound_message` returns the payload and each endpoint's delivery with
its attempts. Delivery status: `preparing`, `received` (queued), `sent`
(delivered), `stalled` (retry scheduled), `failed` (retries exhausted) or
`rejected` (skipped: endpoint paused/disabled, or dropped by a Function).
Acceptance is not delivery.

## What customers receive

Every delivery carries `webhook-id`, `webhook-timestamp` and `webhook-signature`
(`v1,` + base64 HMAC-SHA256 over `id.timestamp.body`, keyed with the endpoint's
`whsec_` secret), plus informational `webhook-event-type` and
`webhook-consumer`. Any Standard Webhooks library verifies it, including Svix's.
Send customers https://webhookrelay.com/docs/outbound/receiving.

Retries: 5s, 5m, 30m, 2h, 5h, 10h, 10h (8 attempts) within 48 hours.
`Retry-After` on 429/503 is honoured (up to 1 hour). Redirects count as
failures; `410 Gone` disables the endpoint. Timeout 15s by default (max 60).

## Endpoints

Fields: `url`, `event_types` (or `["*"]`), `description`, `headers`, `rate`,
`timeout`, `auto_disable`, `function_id`, and on create only `secret`. Rate 0
inherits the consumer's rate, then 50/s. Each endpoint is its own delivery
lane, so a slow customer never delays another. A Function may rewrite the JSON
body or drop the message; retries reuse its saved result.

- `pause_outbound_endpoint` / `resume_outbound_endpoint`
- `rotate_outbound_endpoint_secret`: signs with both secrets for 24 hours
  (refused during that overlap)
- `reveal_outbound_endpoint_secret`: returns the current secret (sensitive)

## Endpoint health

An endpoint is `failing` after 5 failed attempts in a row or one delivery that
ran out of retries; a success makes it `active` again. `auto_disable` endpoints
are disabled after 100 failures in a row over at least 12 hours.

- `get_outbound_health`: endpoint counts by state plus 24h attempts/failures.
- `list_outbound_endpoints` with `state: "failing"` and no consumer: failing
  endpoints across all customers, longest failing first, each with `stats` and
  `failing_since`.

## Recovery

- `retry_outbound_delivery`: `{ "endpoint_id": "...", "message_id": "..." }`
- `recover_outbound_deliveries`: re-send deliveries whose retries were exhausted.
- `replay_missing_outbound_deliveries`: send deliveries skipped while the
  endpoint was paused or disabled (resume it first).

The last two take `endpoint_id` and optional RFC3339 `since` (default 24 hours,
max 35 days) and return a task; poll `get_outbound_recovery_task`. Redelivery
can trigger actions in the customer's system: confirm with the user before
recovering in bulk.

## Migrating from Svix, Hookdeck Outpost, Convoy, Hook0 or DIY

Pass each endpoint's existing signing secret as `secret` when creating it
(`whsec_` + base64 of a 24-64 byte key; the prefix is optional; asymmetric
`whsk_`/`whpk_` keys are refused). The customer keeps verifying with the key it
already has. Read the secret from the old provider's API and pass it straight
through: never print, summarize or log it. Coming from Svix, receivers that use
a Svix library need no change at all (it accepts the unbranded `webhook-*`
headers). Other providers use a different signature scheme, so receivers add
Standard Webhooks verification during a dual-publish window.

Step-by-step agent playbooks (fetch and follow):

- https://webhookrelay.com/outbound-migration/index.md
- https://webhookrelay.com/outbound-migration/svix.md
- https://webhookrelay.com/outbound-migration/hookdeck-outpost.md
- https://webhookrelay.com/outbound-migration/convoy.md
- https://webhookrelay.com/outbound-migration/hook0.md
- https://webhookrelay.com/outbound-migration/diy.md

Not available yet: a customer-facing portal, non-HTTP destinations (queues),
FIFO ordering, more than 1,000 customers per account, and a Python SDK.

## References

- Agent setup guide: https://webhookrelay.com/outbound-webhooks.md
- Docs: https://webhookrelay.com/docs/outbound.md
- Receiving and verifying (for your customers): https://webhookrelay.com/docs/outbound/receiving.md
- Operating (health, recovery, limits): https://webhookrelay.com/docs/outbound/operating.md
- Product page: https://webhookrelay.com/outbound-webhooks/
- Dashboard: https://my.webhookrelay.com/outbound
