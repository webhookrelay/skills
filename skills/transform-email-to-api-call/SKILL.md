---
name: transform-email-to-api-call
description: >-
  Turn inbound emails into calls to your own API. Configure a Webhook Relay
  bucket with an inbound email address, forward it to your API's URL, and attach
  a JavaScript function that reshapes the parsed email into exactly the JSON
  (and headers / method / path) your endpoint expects. Use for email-driven
  automation — create a ticket / lead / record from an email, forward parsed
  order confirmations to an internal API, or adapt inbound mail to any
  third-party API shape. Triggers: "when I get an email call my API", "turn
  emails into API calls", "email to webhook automation", "transform inbound
  email and POST to my endpoint", "parse an email and send it to my service",
  "email-driven workflow". Combines Webhook Relay inbound email, a public
  output, and a transform function. See email-parsing-api for the raw payload
  and webhook-transformations for the full function API.
---

# Transform an inbound email into an API call

Wire an email address straight to your API: mail arrives, Webhook Relay parses
it to JSON, a function reshapes it into your API's request, and the bucket's
output POSTs it — all server-side, no agent to run.

```text
Sender ──▶ <id>@in.webhookrelay-mail.com ──▶ bucket ──▶ function ──▶ POST https://api.example.com/…
(email)         (inbound address)          (parsed JSON)  (reshape)     (your API's shape)
```

## Tooling preference

Use the Webhook Relay MCP server first when it is connected. This workflow is
mostly account configuration: create the bucket, create an email input, create
and test the transform function, create the output, and inspect delivery logs.

Use the `relay` CLI only when MCP is not connected but the CLI is authenticated
and working, or when you need to run an internal forwarding agent for a private
destination.

## 1. Create a bucket with an inbound email address

With MCP, create the bucket, then create an email input on it with
`create_email_input`. Keep the returned inbound address; that is the address to
hand out or point mail at. If the destination is public, create the bucket with
the destination URL or add a public output with the available MCP output tool.

CLI fallback:

```bash
relay email create --bucket email-to-api
# → prints the address, e.g. <id>@in.webhookrelay-mail.com  (hand it out / point mail at it)
```

`--filter-from <addr>` restricts who may send; other mail is dropped.

## 2. Write the transform function

The function receives the **parsed email** as `r.body` (the JSON from the
email-parsing-api skill) and rewrites the request into what your API expects.
See `examples/email-to-api.js` — it maps an email into a create-ticket call:

```javascript
// email-to-api.js — parsed email → your API's request.
let email
try {
  email = JSON.parse(r.body)
} catch (e) {
  r.setResponseStatus(400); r.setResponseBody("invalid email payload"); r.stopForwarding()
}

if (email) {
  // Optional: only act on expected mail; drop the rest.
  // if (!/support@yourco\.com/.test(email.recipient)) { r.stopForwarding() }

  const ticket = {
    subject:        email.subject || "(no subject)",
    requester:      email.from,
    requester_name: email.from_name || email.from,
    body:           email.text || email.html || "",
    received_at:    email.date,
    external_id:    email.message_id,   // de-dupe key
  }

  r.setBody(JSON.stringify(ticket))
  r.setMethod("POST")
  r.setHeader("Content-Type", "application/json")
  const token = cfg.get("API_TOKEN")           // keep secrets in function config
  if (token) { r.setHeader("Authorization", "Bearer " + token) }
}
```

Key function API: `r.body` (incoming parsed email), `JSON.parse` / `JSON.stringify`,
`r.setBody`, `r.setHeader` / `r.deleteHeader`, `r.setMethod`, `r.setPath` /
`r.setRawQuery`, `cfg.get("KEY")` for secrets, and `r.stopForwarding()` to drop a
message. Full reference and more helpers: the `webhook-transformations` skill and
https://webhookrelay.com/docs/webhooks/functions/manipulating-json.md

## 3. Test it before attaching

Prefer MCP `create_function` and `execute` with a parsed email payload from the
`email-parsing-api` skill. Iterate until the transformed request matches the
API contract.

CLI fallback: `relay function test` runs the function against sample requests —
use a parsed email as the input body. See `examples/spec.yaml`:

```bash
relay function test -f examples/spec.yaml -v
```

## 4. Create the function and attach it to a public output

With MCP, create the function, configure any required secret values through the
dashboard or available function-config tooling, then attach the function to the
public output. If the bucket/output does not exist yet, pass the function ID
when creating the output or bucket.

CLI fallback:

```bash
# Deploy the function
relay function create --name email-to-api --driver js --source examples/email-to-api.js

# Store the secret it reads via cfg.get("API_TOKEN")
relay function config set email-to-api API_TOKEN=xxxxx

# Point the bucket's output at YOUR API, running the function on the way out
relay output create api --bucket email-to-api --type public \
  --destination https://api.example.com/tickets \
  --function email-to-api
```

The function reads its API token via `cfg.get("API_TOKEN")`; set it with
`relay function config set` (above) — or in the
[dashboard](https://my.webhookrelay.com) (Functions → your function → Config) —
so it isn't hard-coded in source. List or remove values with
`relay function config ls|rm <function>`.

`--type public` means Webhook Relay delivers server-side — nothing to keep
running. To reach a service with no public IP (localhost / private LAN), use an
internal output and a running agent instead (see `webhook-forwarding-internal`).

## 5. Send a test email and verify

Email the address from step 1, then check delivery with MCP
`list_webhook_logs` / `get_webhook_log` or in the Webhook Relay dashboard logs
(request in, transformed request out, and your API's response). To eyeball
exactly what gets sent, temporarily point the output at https://bin.webhookrelay.com
and inspect the captured request.

## Tips

- **Guard the parse.** Wrap `JSON.parse` in try/catch and return a 400 +
  `stopForwarding()` on bad input, so malformed mail never hits your API.
- **Filter early.** Use `--filter-from` on the address and/or check
  `email.recipient` / `email.subject` in the function, calling
  `r.stopForwarding()` to ignore mail you don't want.
- **Secrets** belong in `cfg.get(...)` — set them with
  `relay function config set <function> KEY=VALUE` (or in the dashboard), never
  in source.
- **Per-destination shaping.** A function on an output only changes what that
  destination receives; add more outputs (each with its own function) to fan one
  email out to several APIs in different shapes.
- **Attachments** arrive base64 in `email.attachments[]`; drop or cap them with
  input policy if you don't need them.

## References

Webhook Relay docs (these `.md` URLs render as plain markdown for easy reading):
- Manipulating JSON in functions: https://webhookrelay.com/docs/webhooks/functions/manipulating-json.md
- Functions overview: https://webhookrelay.com/docs/webhooks/functions.md
- Read & modify request data: https://webhookrelay.com/docs/webhooks/functions/modify-request.md
- Make outbound HTTP requests: https://webhookrelay.com/docs/webhooks/functions/make-http-request.md
- Receive emails as webhooks: https://webhookrelay.com/docs/email.md
- Email payload reference: https://webhookrelay.com/docs/email/payload.md
- Forward to a public URL: https://webhookrelay.com/docs/webhooks/public/public-destination.md
- Install the CLI: https://webhookrelay.com/docs/installation/cli.md
