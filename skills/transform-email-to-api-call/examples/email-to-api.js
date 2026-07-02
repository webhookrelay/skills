// email-to-api.js
// Transform a parsed inbound email into a call to your own API.
// Attach to a PUBLIC output whose destination is your API endpoint:
//   relay function create --name email-to-api --driver js --source email-to-api.js
//   relay output create api -b email-to-api --type public \
//     -d https://api.example.com/tickets --function email-to-api

let email
try {
  email = JSON.parse(r.body)
} catch (e) {
  // Malformed payload: reject it and don't call the API.
  r.setResponseStatus(400)
  r.setResponseBody("invalid email payload")
  r.stopForwarding()
}

if (email) {
  // Optional: only act on mail to an expected address / from a known sender.
  // Anything else is ignored (never reaches your API).
  // if (!/support@yourco\.com/.test(email.recipient || "")) {
  //   r.stopForwarding()
  // }

  // Map the parsed email into the JSON your API expects.
  const ticket = {
    subject:        email.subject || "(no subject)",
    requester:      email.from,
    requester_name: email.from_name || email.from,
    body:           email.text || email.html || "",
    received_at:    email.date,
    external_id:    email.message_id, // use as an idempotency / de-dupe key
  }

  r.setBody(JSON.stringify(ticket))
  r.setMethod("POST")
  r.setHeader("Content-Type", "application/json")

  // Keep the API token in function config (set it per-function in the
  // Webhook Relay dashboard), not in source.
  const token = cfg.get("API_TOKEN")
  if (token) {
    r.setHeader("Authorization", "Bearer " + token)
  }
}
