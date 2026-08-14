# EPrints DataCite REST

A safety-focused modernization of the EPrints User Group **DataCiteDoi** plugin
for the DataCite REST API and DataCite Metadata Schema 4.7.

> **Release status:** 0.1.0-alpha. The core has been extracted from production
> workflows that were validated repository-by-repository, but the genericized
> public package still requires installation testing on a clean EPrints
> instance before a stable release.

## What changes from the historical plugin

The upstream DataCiteDoi plugin used the older MDS workflow. This derivative
keeps the EPrints integration model but introduces a deliberately conservative
REST workflow:

- DataCite REST API;
- DataCite Metadata Schema 4.7;
- no automatic DOI minting;
- read-only classifier and authenticated preflight;
- exact DataCite client ownership verification;
- Draft-first DOI creation;
- separate explicit publication to `Findable`;
- local DOI persistence only after remote verification;
- duplicate barriers for external/historical DOI-like identifiers;
- exact EPrints current-user write allowlist;
- one write request, no automatic retry;
- authenticated GET after every write;
- semantic comparison for modern records;
- idempotent `UPDATE_NOOP`;
- narrowly scoped partial update support (currently exact HTTP -> HTTPS
  landing URL migration).

## Source layout

```text
lib/plugins/EPrints/Plugin/Event/DataCiteEventREST.pm
lib/plugins/EPrints/Plugin/Export/DataCiteXMLREST.pm
lib/plugins/EPrints/Plugin/Screen/EPrint/Staff/DataCiteREST.pm
cfg/cfg.d/z_datacitedoi_rest.example.pl
cfg/cfg.d/z_datacite_mapping.example.pl
cfg/lang/en/phrases/datacite_rest.xml
```

## Installation sketch

1. Install/copy the plugin files into the corresponding EPrints tree.
2. Add a dedicated `doi` eprint field if the repository does not already have
   one. Do **not** blindly repurpose a historical identifier field.
3. Copy the example configuration into the archive-local `cfg/cfg.d` tree.
4. Configure the managed DOI namespace and exact DataCite `client_id`.
5. Store the repository API key in a protected external file; never in Git.
6. Adapt the metadata mapping to the repository schema.
7. Run `epadmin test <archive>` and validate generated XML against DataCite 4.7.
8. Test CLI write denial before exposing web write actions.

See `docs/SECURITY_MODEL.md`, `docs/ARCHITECTURE.md` and
`docs/VALIDATION.md` before enabling writes.

## Upstream and license

This project is a derivative/modernization of
[`eprintsug/DataCiteDoi`](https://github.com/eprintsug/DataCiteDoi), whose
installed package identifies Rory McNicholl as creator and is distributed
under the GNU General Public License v3. The exact GPLv3 license shipped with
the installed upstream package is included as `LICENSE`.

Substantial REST/safety modifications were developed for production EPrints
repositories in 2026 and then generalized for this package.

This project is not an official DataCite product and not an official EPrints
release.

## DataCite documentation

- REST API: <https://support.datacite.org/docs/api>
- Updating metadata: <https://support.datacite.org/docs/updating-metadata-with-the-rest-api>
- DOI states: <https://support.datacite.org/docs/doi-states>
- Metadata Schema 4.7: <https://schema.datacite.org/meta/kernel-4.7/>
