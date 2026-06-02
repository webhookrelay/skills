// filter.js
// Only forward webhooks for the "production" environment; drop everything else.
// Demonstrates conditional forwarding with r.stopForwarding().

let data = {}
try {
  data = JSON.parse(r.body)
} catch (e) {
  // Not JSON — let it pass through unchanged, or drop it; here we drop.
  r.stopForwarding()
}

if (data.environment && data.environment !== "production") {
  console.log("dropping non-production event:", data.environment)
  // Acknowledge the provider so it doesn't retry, but don't forward.
  r.setResponseStatus(200)
  r.setResponseBody("ignored")
  r.stopForwarding()
}
