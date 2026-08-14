# Source comparison

The generic core was extracted from the installed upstream DataCiteDoi package
and two repository-local REST implementations that had been validated in
production workflows.

## Approximate source scale at extraction

| Source | Event | Exporter | Staff Screen |
|---|---:|---:|---:|
| installed upstream DataCiteDoi | 208 lines | 81 lines | 146 lines |
| repository-local FedOA branch | 1,953 lines | 116 lines | — |
| repository-local RM Open Archive branch | 3,690 lines | 138 lines | 1,857 lines |

The public generic Event is based primarily on the more complete second REST
branch because it contains the later safety work: duplicate barriers,
authenticated ownership verification, exact write-user gate, Draft/Findable
separation, semantic comparison and idempotent updates.

## What was generalized

The public core does **not** contain production values for:

- DOI prefix or suffix namespace;
- DataCite client ID;
- repository API-key path;
- EPrints user IDs;
- repository publisher names;
- institutional RORs;
- production hostnames;
- repository-specific type vocabularies.

Instead, the Event accepts configuration/callbacks for canonical DOI creation,
managed DOI recognition, duplicate-barrier fields, mintable types and metadata
preflight. Metadata semantics remain in mapping callbacks.

## Upstream delta

The historical Event performs an MDS-style mint/register operation. The REST
core is a substantial rewrite rather than a small endpoint substitution. The
most important behavioral differences are documented in `ARCHITECTURE.md` and
`SECURITY_MODEL.md`.
