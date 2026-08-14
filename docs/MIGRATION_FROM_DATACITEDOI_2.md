# Migration from historical DataCiteDoi

Do not enable this package by simply replacing the historical Event plugin.
Audit each repository first.

1. Inventory the field currently used for DOI/external identifiers.
2. Add a dedicated DOI field when external and managed identifiers are mixed.
3. Inventory existing DataCite DOI and exact client ownership.
4. Define managed DOI namespace callbacks, including legacy patterns.
5. Configure duplicate-barrier fields.
6. Disable automatic minting and the historical MDS write path.
7. Create a dedicated API key file for the repository.
8. Validate the metadata mapping and mandatory-field census.
9. Test read-only preflight and CLI denial.
10. Only then enable explicit Staff Screen writes.

Legacy schema migrations are intentionally not automatic.
