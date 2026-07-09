---
name: webhook-transformations
description: >-
  Write, test, and attach JavaScript (or Lua) transformation functions that run
  on Webhook Relay to modify webhooks in flight — reshape the JSON body, rename/
  reformat fields, add or remove headers, change the method/path, set the
  response, conditionally drop requests, or call out to other HTTP APIs. Use
  whenever a destination expects a different payload shape than the provider
  sends (e.g. converting a generic event into a Slack/Discord/Teams message,
  adapting one provider's webhook for another service, filtering, enriching, or
  signing requests). Triggers: "transform a webhook", "convert this payload to
  Slack format", "modify the webhook body/headers before forwarding", "drop
  webhooks that don't match", "webhook relay function". Pairs with the
  webhook-forwarding-internal / -public skills (attach the function to an output
  or input).
---

# Transforming webhooks with JavaScript functions

A **function** is server-side code attached to an input or output. It runs on
every request that passes through and can rewrite the request before it is
forwarded, set a custom response, or stop forwarding entirely. The default and
recommended runtime is **JavaScript** (driver `js`, powered by goja). Lua
(`lua`) is also supported.

Where a function runs:
- attached to an **output** → transforms the **request** just before it is
  delivered to that destination (most common — e.g. format for Slack).
- attached to an **input** → can modify the request on the way in and craft the
  **response** returned to the provider.

## The function API (JavaScript)

Your code runs against a global request object `r`. There is no `function(){}`
wrapper — just write top-level statements.

**Read the incoming request** (read-only):
- `r.body` — raw request body string
- `r.method`, `r.path`, `r.rawQuery`
- `r.headers` — map of request headers
- `r.query` — parsed query params
- `r.formData` — parsed form data

**Mutate the request** (forwarded to the destination):
- `r.setBody(string)`
- `r.setHeader(name, value)` / `r.deleteHeader(name)`
- `r.setMethod(string)` — e.g. `"POST"`
- `r.setPath(string)` / `r.setRawQuery(string)`

**Control the response** returned to the original caller:
- `r.setResponseBody(string)`
- `r.setResponseStatus(code)` — e.g. `200`, `400`
- `r.setResponseHeader(name, value)`

**Flow control:**
- `r.stopForwarding()` — do not forward this request (use for filtering/dropping)

**Other globals:**
- `JSON.parse(...)` / `JSON.stringify(...)` — standard, always available; use
  these for JSON.
- `cfg.get("KEY")` — read a stored config value / secret so you never hard-code
  tokens. Set values with `relay function config set <function> KEY=VALUE` (or in
  the dashboard); list/remove with `relay function config ls|rm <function>`.
- `console.log(...)` / `console.warn(...)` / `console.error(...)` — appear in
  function logs.

> Newer platform versions also expose helper modules (`http` for outbound calls,
> `crypto` for hashing/HMAC/base64, `time`, plus `mailgun`/`bigquery`). Prefer
> the standard `JSON` + `r.*` API above for portability; reach for the modules
> only when needed and confirm availability in the dashboard. See
> https://webhookrelay.com/docs/webhooks/functions for the current reference.

camelCase, `setBody`-style, and PascalCase (`SetRequestBody`) names are all
accepted; this skill uses the idiomatic camelCase aliases.

## Tooling preference

Use the Webhook Relay MCP server first when it is connected. It can create
functions, execute them with synthetic requests, attach them to inputs/outputs,
and inspect delivery logs after live traffic runs through them.

Use the `relay` CLI only when MCP is not connected but the CLI is authenticated
and working, or when you need a CLI-only capability such as local file-based test
specs.

## Workflow

### 1. Write the function
Put the code in a `.js` file. See `examples/` in this skill:
- `examples/to-slack.js` — reshape a generic event into a Slack message
- `examples/filter.js` — drop requests that don't match a condition
- `examples/add-auth-header.js` — inject an auth header from config
- `examples/spec.yaml` — a test spec for `relay function test`

If the Webhook Relay MCP server exposes runtime docs, read its JavaScript API
resource before writing or updating code. JavaScript transforms run in a custom
runtime and mutate the global `r` object directly; do not write Node.js/browser
code or handler wrappers.

### 2. Create and test with MCP

When MCP is connected:

1. Create the function with `create_function` (`driver: js`).
2. Execute it with realistic method/path/query/headers/body values using
   `execute`.
3. Iterate until the returned request/response mutation is correct.
4. Attach it to an input or output with `attach_function`, or pass the function
   ID while creating a bucket/output.

For output formatting, prefer attaching the function to the output so other
outputs in the same bucket can receive the original request if needed.

### 3. CLI fallback: test locally with a spec

`relay function test` runs your code against sample requests and asserts the
result. Use this when MCP is unavailable or when a checked-in spec file is the
most convenient validation path. **Set `driver: js`** in the spec (the `.js`
extension also implies it).

```bash
relay function test -f examples/spec.yaml -v
```

Assertions available under `expect.request` / `expect.response`:
`bodyModified`, `bodyEquals`, `bodyContains`, `headerModified`, `headerEquals`,
`methodEquals`, `pathEquals`, `pathContains`, `queryContains`, `statusEquals`.

> **CLI version note.** `relay function test` and `relay function invoke` for
> **JavaScript** need a recent `relay` CLI. Older versions fail with a Lua
> `syntax error` on `.js` files (the driver wasn't honored) or
> `unknown field "metadata" in reactor_v1.Request` on invoke. If you hit either,
> run `relay --version` and update the CLI (https://webhookrelay.com/docs/installation/cli).
> Deployed functions run server-side and are unaffected.

### 4. CLI fallback: create (deploy) the function
```bash
relay function create --name to-slack --driver js --source examples/to-slack.js
relay function ls
```
Update later with:
```bash
relay function update to-slack --source examples/to-slack.js
```

### 5. CLI fallback: attach it to an output (or input)
```bash
# attach when creating the output
relay output create -b to-slack --type public \
  -d https://hooks.slack.com/services/T000/B000/XXXX \
  --function to-slack

# or attach inline while forwarding
relay forward --type public -b to-slack -f to-slack \
  https://hooks.slack.com/services/T000/B000/XXXX

# attach to an input instead (to shape the response to the provider)
relay input create -b my-app "incoming" --function to-slack
```

### 6. CLI fallback: invoke ad-hoc
```bash
relay function invoke to-slack -m POST -b '{"message":"deploy finished"}' \
  --header content-type=application/json
```

## Minimal example

```javascript
// Convert a generic JSON webhook into a Slack message.
const data = JSON.parse(r.body)
r.setBody(JSON.stringify({ text: "New event: " + (data.message || "n/a") }))
r.setHeader("Content-Type", "application/json")
```

## Tips
- Always `JSON.stringify` before `r.setBody` — the body is a string.
- Guard against malformed input (wrap `JSON.parse` in try/catch; set a 400
  response and `stopForwarding()` on bad payloads).
- Keep secrets in `cfg.get(...)`, not in source.
- A function attached to an output only changes what that destination receives;
  other outputs in the bucket are unaffected — great for per-destination
  formatting in a fan-out.
- Iterate with MCP `execute` before attaching to live traffic. If MCP is not
  available, use `relay function test` before deploying.

## References

Webhook Relay function docs (these `.md` URLs render as plain markdown for easy reading):
- Functions overview: https://webhookrelay.com/docs/webhooks/functions.md
- Read & modify request data: https://webhookrelay.com/docs/webhooks/functions/modify-request.md
- Encode/decode JSON: https://webhookrelay.com/docs/webhooks/functions/manipulating-json.md
- Crypto (base64, hmac, sha/md5, encrypt): https://webhookrelay.com/docs/webhooks/functions/crypto-functions.md
- Make outbound HTTP requests: https://webhookrelay.com/docs/webhooks/functions/make-http-request.md
- Working with time: https://webhookrelay.com/docs/webhooks/functions/working-with-time.md
- Accessing metadata: https://webhookrelay.com/docs/webhooks/functions/accessing-metadata.md
- Parse multipart form data: https://webhookrelay.com/docs/webhooks/functions/multipart-form-data.md — URL-encoded form: https://webhookrelay.com/docs/webhooks/functions/url-encoded-data.md
- Send emails (Mailgun): https://webhookrelay.com/docs/webhooks/functions/send-emails.md — BigQuery: https://webhookrelay.com/docs/webhooks/functions/big-query.md
- Deploy functions from CI/CD: https://webhookrelay.com/docs/webhooks/functions/integrate-into-cicd.md
