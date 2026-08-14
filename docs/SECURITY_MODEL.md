# Security model

## Hard write gate

Write authorization comes only from `Repository->current_user()`. A caller may
not supply an acting userid. CLI calls therefore fail before credentials are
resolved.

## Fail-closed Staff Screen

Remote writes from the Staff Screen require two independent local conditions:

1. the authenticated EPrints userid is explicitly present in
   `datacitedoi.write_userids`;
2. `datacitedoi.web_writes_enabled` is explicitly true.

The default example configuration sets `web_writes_enabled = 0`. A missing or
false setting therefore leaves the Staff Screen in preflight/preview-only mode.

The Screen repeats this policy both in its `allow_*` methods and inside each
write `action_*`. The Event layer then independently applies its own hard
authenticated-user gate and fresh DataCite checks before a remote request.

## Credentials

Use a dedicated repository API-key file outside committed configuration. The
key is read only after local authorization and explicit confirmation gates.
Never log the Authorization header or key contents.

## No blind updates

Every update requires a fresh authenticated GET and exact DataCite client
ownership verification. A shared DOI prefix is not proof of ownership.

## One request, no retry

Every write path sends exactly one POST or PUT. If final state cannot be
verified, return a warning state and reconcile with a fresh GET; do not retry
automatically.

## Duplicate barriers

Historical/external identifier fields are scanned conservatively for DOI-like
identifiers. A second DOI is blocked unless an explicit migration reconciles a
managed DOI into the dedicated DOI field.

## Persistence

A newly published DOI is persisted locally only after an authenticated GET
confirms exact DOI, configured client, landing URL and state `findable`.
