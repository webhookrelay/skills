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
- `cfg.get("KEY")` — read a stored config value / secret (set per-function in
  the dashboard) so you never hard-code tokens.
- `console.log(...)` / `console.warn(...)` / `console.error(...)` — appear in
  function logs.

> Newer platform versions also expose helper modules (`http` for outbound calls,
> `crypto` for hashing/HMAC/base64, `time`, plus `mailgun`/`bigquery`). Prefer
> the standard `JSON` + `r.*` API above for portability; reach for the modules
> only when needed and confirm availability in the dashboard. See
> https://webhookrelay.com/docs/webhooks/functions for the current reference.

camelCase, `setBody`-style, and PascalCase (`SetRequestBody`) names are all
accepted; this skill uses the idiomatic camelCase aliases.

## Workflow

### 1. Write the function
Put the code in a `.js` file. See `examples/` in this skill:
- `examples/to-slack.js` — reshape a generic event into a Slack message
- `examples/filter.js` — drop requests that don't match a condition
- `examples/add-auth-header.js` — inject an auth header from config
- `examples/spec.yaml` — a test spec for `relay function test`

### 2. Test locally with a spec (no deployment needed)
`relay function test` runs your code against sample requests and asserts the
result. **Set `driver: js`** in the spec (the `.js` extension also implies it).

```bash
relay function test -f examples/spec.yaml -v
```

Assertions available under `expect.request` / `expect.response`:
`bodyModified`, `bodyEquals`, `bodyContains`, `headerModified`, `headerEquals`,
`methodEquals`, `pathEquals`, `pathContains`, `queryContains`, `statusEquals`.

### 3. Create (deploy) the function
```bash
relay function create --name to-slack --driver js --source examples/to-slack.js
relay function ls
```
Update later with:
```bash
relay function update to-slack --source examples/to-slack.js
```

### 4. Attach it to an output (or input)
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

### 5. Invoke ad-hoc (quick smoke test against the deployed function)
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
- Iterate with `relay function test` before deploying; it's faster than
  round-tripping through a live webhook.
