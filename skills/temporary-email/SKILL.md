---
name: temporary-email
description: >-
  Create a disposable / temporary inbound email address from the terminal with
  the relay CLI and read the mail it receives as JSON — no mailbox, SMTP server,
  or per-address signup. Use to grab a throwaway inbox for a signup / OTP /
  confirmation link, receive one-off mail in a script or test, or watch an
  address for incoming messages. Triggers: "temporary email", "disposable email
  address", "throwaway inbox", "burner email", "get an email address to receive
  a code / OTP / confirmation link", "read incoming email from the CLI", "test
  an email signup flow". Built on Webhook Relay inbound email plus the
  pull-delivery events queue. See also email-parsing-api (inbound email as a
  JSON API) and transform-email-to-api-call (reshape and forward it).
---

# Temporary / disposable email addresses

Create an inbound email address in one command, receive mail at it, and read
each message as clean JSON — without running an SMTP server, opening a mailbox,
or signing up per address. The address is backed by a Webhook Relay **bucket**;
mail sent to it is parsed and queued, and you pull it with `relay events`.

Great for grabbing a throwaway inbox to catch a signup confirmation, a one-time
code, or any "send me an email" step in a script or test.

## Prerequisites

1. `relay` CLI installed: https://webhookrelay.com/docs/installation/cli (the
   `email` and `events` commands need a recent version).
2. Logged in: `relay login` (or set `RELAY_KEY` / `RELAY_SECRET`). Confirm with
   `relay bucket ls`.

## 1. Create an address

No arguments creates a throwaway bucket and prints a ready-to-use address:

```console
$ relay email create
Inbound email address created.

  Address:  eb9649a3-b781-4158-be69-bb210596e759@in.webhookrelay-mail.com
  Bucket:   email-c8e44869  (9bf342ce-9582-42ea-8662-ac73d60e2db6, created for you)
  Input:    eb9649a3-b781-4158-be69-bb210596e759

Poll it with:
  relay events --bucket email-c8e44869 --follow
```

The address is `<input-id>@in.webhookrelay-mail.com`. Hand it to whatever needs
to email you. For scripts, `--json` gives you the address and bucket to capture:

```bash
JSON=$(relay email create --json)
ADDR=$(echo "$JSON" | jq -r .email_address)
BUCKET=$(echo "$JSON" | jq -r .bucket_name)
```

Options: `--bucket <name|id>` to use an existing bucket, `--name` to label the
input, `--filter-from <addr>` to only accept mail from a given sender
(repeatable), `--no-attachments` to skip attachments.

## 2. Read the mail

`relay events` consumes the bucket's queue: each poll returns the messages that
haven't been read yet and marks them delivered, so repeated polls drain it.

```bash
# One-shot: print any new emails (sender + subject)
relay events --bucket "$BUCKET"

# Wait for mail to arrive and print each as it lands (Ctrl-C to stop)
relay events --bucket "$BUCKET" --follow

# Raw parsed-email JSON (one per line) — good for jq
relay events --bucket "$BUCKET" --body

# Full event objects
relay events --bucket "$BUCKET" --json
```

See `examples/wait-for-email.sh` for a create-and-wait helper.

## 3. Extract a value (OTP, confirmation link)

The body is the parsed email; pull what you need with `jq`:

```bash
# Grab a 6-digit code from the text body of the next email
relay events --bucket "$BUCKET" --body | jq -r '.text' | grep -oE '[0-9]{6}' | head -1

# Grab the first confirmation link
relay events --bucket "$BUCKET" --body | jq -r '.html, .text' | grep -oE 'https?://[^"[:space:]]+' | head -1
```

Each parsed message looks like:

```json
{
  "from": "no-reply@service.com",
  "from_name": "Service",
  "recipient": "eb9649a3-…@in.webhookrelay-mail.com",
  "to": ["eb9649a3-…@in.webhookrelay-mail.com"],
  "subject": "Your verification code",
  "text": "Your code is 481920.",
  "date": "Fri, 03 Jul 2026 09:00:00 +0000",
  "message_id": "<abc@service.com>"
}
```

`html`, `cc` and `attachments` appear when present. See the
[payload reference](https://webhookrelay.com/docs/email/payload.md) for every field.

## 4. Manage & clean up

```bash
relay email list --bucket "$BUCKET"   # show the bucket's addresses
relay bucket rm "$BUCKET"             # delete the inbox when you're done
```

## Tips

- **Consuming queue.** `relay events` marks messages delivered as it returns
  them, so they won't come back on the next poll — perfect for "process each
  email once". For a non-destructive view of everything received, use
  `relay logs --bucket <b>` and `relay inspect`.
- **Lock it down.** Inbound addresses are public. Add `--filter-from` so only an
  expected sender is accepted; other mail is silently dropped.
- **Keep the address.** A throwaway bucket (and its address) lives until you
  `relay bucket rm` it, so you can reuse the same inbox across a session.
- Need to *do something* with each email automatically (forward it, call your
  API)? See the transform-email-to-api-call skill.

## References

Webhook Relay docs (these `.md` URLs render as plain markdown for easy reading):
- Receive emails as webhooks: https://webhookrelay.com/docs/email.md
- Create & poll addresses from the CLI: https://webhookrelay.com/docs/email/cli.md
- Email payload reference: https://webhookrelay.com/docs/email/payload.md
- Sender filtering & policy: https://webhookrelay.com/docs/email/filtering-and-policy.md
- Install the CLI: https://webhookrelay.com/docs/installation/cli.md
