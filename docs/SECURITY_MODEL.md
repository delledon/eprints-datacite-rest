# Security model

## Hard write gate

Write authorization comes only from `Repository->current_user()`. A caller may
not supply an acting userid. CLI calls therefore fail before credentials are
resolved.

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
