# Architecture

## Separation of concerns

1. **Classifier** — local, no network, decides MINT/UPDATE/BLOCK modes.
2. **Authenticated preflight** — Member API GET, ownership/state/schema checks.
3. **Exporter** — deterministic XML for an explicit DOI; never mints.
4. **Event write layer** — repeats all safety checks and performs exactly one write.
5. **Staff Screen** — read-only preflight/preview by default; explicit
   second-step write actions are additionally gated by
   `web_writes_enabled = 1`.

## Web write gating

The Staff Screen is fail-closed. With `web_writes_enabled` absent or false,
preflight and preview actions remain available to explicitly allowlisted users,
but `CREATE_DRAFT`, `PUBLISH_FINDABLE`, and `UPDATE_URL_HTTPS` are denied.

When web writes are explicitly enabled, the Screen checks both the current-user
allowlist and the global write gate in its permission methods and again inside
the write actions. The Event layer independently repeats its authenticated-user
and DataCite safety checks immediately before any remote write.

## Creation

```text
classifier -> authenticated GET (404) -> local XML/payload preview
-> CREATE_DRAFT -> POST /dois -> authenticated GET(state=draft)
-> publish preview -> PUBLISH_FINDABLE -> one PUT(event=publish)
-> authenticated GET(state=findable) -> persist DOI locally
```

## Update

Modern updates compare local and remote XML semantically by top-level DataCite
property. If effective state already agrees, the result is `UPDATE_NOOP` and no
PUT is sent. The included write path permits only an exact HTTP-to-HTTPS URL
upgrade while metadata are semantically identical.

## Repository policy hooks

The generic Event supports callbacks for:

- `canonical_doi`;
- `managed_doi_eprintid`;
- `metadata_preflight`.

This keeps legacy namespaces and repository metadata rules outside the core.
