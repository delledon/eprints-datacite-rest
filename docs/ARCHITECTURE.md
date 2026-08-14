# Architecture

## Separation of concerns

1. **Classifier** — local, no network, decides MINT/UPDATE/BLOCK modes.
2. **Authenticated preflight** — Member API GET, ownership/state/schema checks.
3. **Exporter** — deterministic XML for an explicit DOI; never mints.
4. **Event write layer** — repeats all safety checks and performs exactly one write.
5. **Staff Screen** — preview and explicit second-step write actions.

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
