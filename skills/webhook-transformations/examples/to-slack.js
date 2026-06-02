// to-slack.js
// Reshape a generic JSON webhook into a Slack-compatible message.
// Attach to a public output pointing at an incoming Slack webhook URL.

let data
try {
  data = JSON.parse(r.body)
} catch (e) {
  // Bad payload: reject it and don't forward to Slack.
  r.setResponseStatus(400)
  r.setResponseBody("invalid JSON body")
  r.stopForwarding()
}

if (data) {
  const text = "New event: " + (data.message || data.text || JSON.stringify(data))
  r.setBody(JSON.stringify({ text: text }))
  r.setHeader("Content-Type", "application/json")
}
