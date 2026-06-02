// add-auth-header.js
// Inject an Authorization header (read from function config, not hard-coded)
// so the destination API accepts the relayed request.
//
// Set the secret once in the dashboard for this function, e.g. a config value
// named DEST_TOKEN, then reference it with cfg.get("DEST_TOKEN").

const token = cfg.get("DEST_TOKEN")
if (token) {
  r.setHeader("Authorization", "Bearer " + token)
}
r.setHeader("X-Forwarded-By", "webhookrelay")
