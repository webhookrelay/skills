---
name: email-parsing-api
description: >-
  Turn inbound email into structured JSON with Webhook Relay's email parsing.
  Create an inbound address and every message you receive is parsed into a
  stable JSON payload — from, from_name, to/cc (arrays), subject, text, html,
  headers, spf/dkim/dmarc, and attachments (base64) — then delivered to your
  endpoint or pulled from an API. Use to build an "email → JSON" API, ingest
  order confirmations / support mail / reports into your app, or receive email
  programmatically without running an SMTP or IMAP server. Triggers: "parse
  email to JSON", "inbound email API", "email to webhook", "convert an email
  into an API payload", "extract fields from an email programmatically",
  "receive email in my app", "email parsing service". See transform-email-to-
  api-call to reshape the payload before delivery, and temporary-email for quick
  throwaway inboxes.
---

# Email parsing API — inbound email as JSON

Webhook Relay parses inbound email into a predictable JSON document. You get a
unique address; every message sent to it is parsed server-side and handed to
your code — as a webhook `POST` to your endpoint, or pulled from the events API.
No SMTP/IMAP server, MIME parsing, or attachment decoding on your side.

```text
Sender ──▶ <id>@in.webhookrelay-mail.com ──▶ Webhook Relay ──▶ parsed JSON ──▶ your API
(any email)      (your inbound address)        (parse + policy)   (POST application/json)
```

## The parsed payload

Delivered as `Content-Type: application/json` with an
`X-Webhookrelay-Source: email` header. Empty fields are omitted.

| Field | Type | Notes |
| --- | --- | --- |
| `from` | string | Sender address, lower-cased. |
| `from_name` | string | Sender display name, if present. |
| `recipient` | string | The inbound address that matched. |
| `to` | string[] | All `To` addresses (**array**). |
| `cc` | string[] | All `Cc` addresses (array). Omitted when empty. |
| `subject` | string | Email subject. |
| `date` | string | `Date` header, RFC 2822. |
| `message_id` | string | `Message-ID`, useful for de-duplication. |
| `text` | string | Plain-text body. Omitted when absent. |
| `html` | string | HTML body. Omitted when absent. |
| `headers` | object | All parsed headers as a string map. |
| `spf` / `dkim` / `dmarc` | string | Authentication results (`pass`, `fail`, `none`, …). |
| `attachments` | object[] | `name`, `content_type`, `size`, base64 `content`. Omitted when none or dropped. |

A sample document is in `examples/parsed-email.json`. Full field reference:
https://webhookrelay.com/docs/email/payload.md

## Tooling preference

Use the Webhook Relay MCP server first when it is connected. It can create
buckets, email inputs, public/internal outputs, and inspect webhook logs.

Use the `relay` CLI only when MCP is not connected but the CLI is authenticated
and working, or when you need to run the local agent for an internal/private
destination.

## 1. Create an inbound address

With MCP, create or choose a bucket, then create an email input with
`create_email_input`. Keep the returned inbound address.

CLI fallback:

```bash
relay email create --bucket inbound-mail            # prints the address
relay email list --bucket inbound-mail              # recover it later
```

`--filter-from <addr>` restricts senders; `--no-attachments` skips attachment
storage. (You can also add an Email input from the dashboard.)

## 2. Choose how to receive the JSON

**a) Deliver to your public API (server-side, no agent).** Add a public output
pointing at your HTTPS endpoint; every parsed email is POSTed to it 24/7:

Prefer MCP bucket/output configuration when available. CLI fallback:

```bash
relay output create ingest --bucket inbound-mail --type public \
  --destination https://api.example.com/inbound-email
```

**b) Deliver to a local / private service (development).** Use an internal
output delivered by a running agent — see the `webhook-forwarding-internal`
skill:

Use MCP to create the internal output when available, then start only the agent
with CLI:

```bash
relay forward --bucket inbound-mail
```

CLI-only fallback when MCP is unavailable:

```bash
relay forward --bucket inbound-mail http://localhost:8080/inbound-email
```

**c) Pull it from the API (polling consumer).** Drain the parsed messages with
the events queue instead of hosting an endpoint:

```bash
relay events --bucket inbound-mail --json          # full event objects
relay events --bucket inbound-mail --body          # just the parsed-email JSON
```

`--body` maps 1:1 to `GET /v1/events?bucket=inbound-mail` — each poll returns
and consumes the next batch.

## 3. Handle the payload

At your endpoint, `JSON.parse` (or your language's equivalent) the body and read
the fields:

```js
// Example: Node/Express receiver
app.post("/inbound-email", (req, res) => {
  const email = req.body;                 // parsed JSON
  console.log(email.from, "→", email.subject);
  // email.text / email.html / email.attachments[]...
  res.sendStatus(200);
});
```

- **Attachments** are base64 in `attachments[].content`; drop or cap them with
  input policy — see https://webhookrelay.com/docs/email/filtering-and-policy.md
- **Trust**: check `spf` / `dkim` / `dmarc` before acting on a message.
- **De-dupe** on `message_id` if retries are possible.

## Reshape before delivery

Most APIs want a specific shape, not the raw email. Attach a JavaScript function
to the output to map the parsed email into your schema. Prefer MCP
`create_function`, `execute`, and `attach_function` when available — see the
`transform-email-to-api-call` and `webhook-transformations` skills.

## References

Webhook Relay docs (these `.md` URLs render as plain markdown for easy reading):
- Receive emails as webhooks: https://webhookrelay.com/docs/email.md
- Email payload reference: https://webhookrelay.com/docs/email/payload.md
- Create & poll addresses from the CLI: https://webhookrelay.com/docs/email/cli.md
- Sender filtering & policy: https://webhookrelay.com/docs/email/filtering-and-policy.md
- Transform with functions: https://webhookrelay.com/docs/webhooks/functions.md
- Install the CLI: https://webhookrelay.com/docs/installation/cli.md
