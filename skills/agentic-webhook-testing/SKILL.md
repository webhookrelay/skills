---
name: agentic-webhook-testing
description: >-
  Test and debug a webhook integration end to end with an AI coding agent and
  Webhook Relay MCP tools: send a realistic request through a real input, wait
  for delivery, inspect the transformed request and destination response,
  follow function execution logs, fix and retest transforms, and replay only
  when authorized. Use for "have the agent test/debug this webhook", agentic
  webhook testing, MCP webhook debugging, failing delivery diagnosis, or
  transformation-function failures. For a temporary no-account capture URL,
  use webhook-debug; for ordinary setup, use the forwarding skills.
---

# Agentic webhook testing

Use the Webhook Relay MCP server to give the agent a closed evidence loop:

```text
provision or select input -> send -> wait -> inspect -> diagnose
                                      |          |
                                      |          +-> destination response/error
                                      +-> function execution IDs -> console logs
```

Prefer MCP for this workflow. It can exercise the real intake, routing,
transformation, and delivery path without asking the user to reproduce each
step manually. If MCP is unavailable, use `webhook-debug` for capture-only
testing or the relevant forwarding skill plus the `relay` CLI.

## Choose the test boundary

- **Capture only, no account:** use `webhook-debug`. Bins are public and
  temporary; never send secrets or personal data.
- **Real delivery path:** use this skill with an existing Webhook Relay input,
  or create an isolated test bucket when the user has asked for setup.
- **Local/private handler:** configure with `webhook-forwarding-internal`; the
  local `relay` agent must be running.
- **Public destination:** configure with `webhook-forwarding-public`; delivery
  runs server-side.

Do not repoint a production provider, update a live transform, or replay a
production event unless the user authorized that change. Read-only diagnosis
does not imply permission to mutate configuration or redeliver an event.

## The MCP test loop

1. Use `list_buckets` and `get_input`/`get_output` to identify the intended
   input and destination. Reuse existing configuration when appropriate.
2. Build a representative request from the provider's documented sample or a
   captured request. Preserve the method, raw body, content type, signature
   header, path, and query when they affect behavior.
3. Call `send_webhook` with the input ID. This enters through the real webhook
   intake and returns the sender-facing response plus one log ID per delivery.
4. Call `wait_for_webhook_log` for every returned log ID. It returns early when
   the delivery is `sent`, `failed`, `rejected`, or `stalled`. If
   `settled=false`, call it again rather than guessing at the outcome.
5. Inspect the evidence in the settled log:
   - request after input/output functions;
   - destination status, response body, and delivery error;
   - input, output, or response-function execution IDs;
   - routing status, duration, and retry state.
6. For any function execution ID, call `get_function_execution_log`. This shows
   the original and modified request, response context, error, duration, and
   the function's `console.log`/`warn`/`error` output. To investigate a pattern,
   use `list_function_execution_logs` with status/time/configuration filters,
   then open representative failures with `get_function_execution_log`.
7. State the observed failure and its evidence before proposing or applying a
   fix. Distinguish transport failures, destination failures, routing/filter
   decisions, and function failures.

## Fixing a transformation

When the user asked for a fix:

1. Read the MCP JavaScript runtime resource before changing code. Webhook Relay
   functions mutate the global `r` object; they are not Node.js handlers.
2. Read the current function with `get_function` and preserve unrelated logic.
3. Add bounded, useful diagnostic output where needed. Prefer identifiers and
   decisions over whole payloads:

```javascript
const event = JSON.parse(r.body)
console.log("transform", {
  eventId: event.id || "missing",
  eventType: event.type || "unknown",
  route: "billing-events"
})
```

   Never print authorization headers, signature secrets, access tokens, or full
   sensitive bodies. Function logs are persisted; capture redaction is a safety
   net, not a reason to log secrets.
4. Test the candidate with `execute` and realistic success and failure cases.
   Its `logs` field contains console output from that synthetic execution.
5. Update/attach the function only within the configuration the user placed in
   scope.
6. Run `send_webhook` -> `wait_for_webhook_log` again. Follow the new execution
   ID and verify both the transformed request and the destination response.

Use the `webhook-transformations` skill for the full function API and CLI test
fallback. Prefer an output function when only one destination needs reshaping;
an input function changes the shared request before fan-out.

## Replay and production safety

`retry_webhook` redelivers an existing event and can repeat real side effects.
Use it only when the user has asked to replay/retry that event and the target is
clear. Mention the duplicate-processing risk when the destination may not be
idempotent.

- Use `process_policy=skip` to resend the stored processed request without
  re-running rules/functions.
- Use `process_policy=force` only when validating changed rules/functions is
  the point of the replay.
- Prefer `send_webhook` with a synthetic event for ordinary regression tests.

## Report the result

Return a compact evidence trail:

- input and destination tested;
- request case(s) sent;
- final delivery status and destination response;
- transform decision and relevant console lines (with secrets removed);
- root cause and changed configuration/code, if authorized;
- whether the retest passed and whether any production event was replayed.

## References

- MCP setup and tool catalog: https://webhookrelay.com/docs/mcp.md
- Agent skills: https://webhookrelay.com/docs/skills.md
- Functions and execution logging: https://webhookrelay.com/docs/webhooks/functions.md
- General webhook testing: https://webhookrelay.com/blog/how-to-test-webhooks.md
- Troubleshooting workflow: https://webhookrelay.com/blog/how-to-debug-webhooks.md
