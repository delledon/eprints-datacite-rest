# Provenance

The source extraction used two production-hardened repository-local branches
plus the installed EPrints User Group DataCiteDoi package.

Installed package metadata (`DataCiteDoi.epmi`) reports:

- title: `DataCiteDoi - DataCite DOIs for EPrints`;
- version metadata: `2.1.2`;
- creator: Rory McNicholl (`repositories@ulcc.ac.uk`);
- home page: `https://github.com/eprintsug/DataCiteDoi`;
- datestamp: 2019-11-12.

The installed package archive filename observed on the server was
`DataCiteDoi-2.1.0.epm`; note the filename/version-metadata discrepancy.

The exact installed upstream Git checkout was subsequently verified read-only on the production EPrints server:

- upstream remote: `https://github.com/eprintsug/DataCiteDoi.git`;
- installed commit: `bbf501f7d9cd0062d4e002ebfe51ff40847123cb`;
- `git status --short`: empty.

The empty status confirms that the installed upstream working tree contained no local modifications relative to that commit at the time of collection.
