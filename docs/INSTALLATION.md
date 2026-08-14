# Installation notes

This alpha package is intentionally not a one-click EPM yet.

## Files

Copy the three plugin classes to the matching EPrints plugin paths, then adapt
and install the example configuration/mapping in the target archive.

## Dedicated DOI field

A repository that mixes external identifiers and locally managed DOI in one
historical field should first add a dedicated field, for example:

```perl
{
    name => 'doi',
    type => 'text',
    render_value => 'EPrints::Extras::render_possible_doi',
},
```

Apply the normal EPrints database-field update procedure and verify the field
through the EPrints API before enabling the plugin. Do not bulk-copy external
DOI into the managed field.

## Credentials

Create a repository-specific API-key file outside the archive configuration.
The exact permissions depend on the local web-server/service-account model;
use the least privilege that still permits the authenticated web action to
read the file. Never make the credential world-readable.

## First enablement sequence

1. configure with all automatic minting disabled;
2. validate the metadata exporter locally;
3. run authenticated read-only preflight;
4. verify CLI write denial;
5. expose Staff Screen preview actions;
6. create one Draft test DOI under an intended production namespace;
7. independently GET and verify `draft`;
8. publish explicitly and independently verify `findable`;
9. verify local persistence occurred only after Findable;
10. verify a second update preview returns `UPDATE_NOOP`.
