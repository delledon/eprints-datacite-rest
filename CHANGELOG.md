# Changelog

## 0.1.0-alpha — 2026-08-14

- Extracted a generic REST core from validated repository-local implementations.
- Added DataCite REST Member API authentication.
- Added Metadata Schema 4.7 target.
- Added Draft-first creation and explicit Findable publication.
- Added exact current-user write allowlists and external credential files.
- Added a fail-closed Staff Screen gate: web writes are disabled by default
  and require explicit `web_writes_enabled = 1` in addition to the user allowlist.
- Added duplicate DOI barriers and managed-namespace callbacks.
- Added semantic modern-update comparison and `UPDATE_NOOP`.
- Added controlled HTTP-to-HTTPS URL-only partial update.
- Added generic configuration and mapping examples.
