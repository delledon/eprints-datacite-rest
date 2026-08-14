# Repository policy configuration

The generic code deliberately does not encode institutional DOI namespaces.

## Default namespace

Without callbacks, a managed DOI has the form:

```text
<prefix>/<repoid>/<eprintid>
```

## Legacy/current namespaces

Use `canonical_doi` to generate new DOI and `managed_doi_eprintid` to recognize
all namespaces that the repository is responsible for. See
`examples/multiple-managed-namespaces.example.pl`.

## External identifiers

Configure `duplicate_barrier_fields`. A DOI-like identifier found there blocks
a second mint. These fields should not be bulk-migrated into the dedicated DOI
field without remote ownership reconciliation.
