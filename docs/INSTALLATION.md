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
2. leave `web_writes_enabled = 0`;
3. validate the metadata exporter locally;
4. run authenticated read-only preflight;
5. verify CLI write denial;
6. expose and test Staff Screen preflight/preview actions while web writes
   remain disabled;
7. verify all three Staff Screen write actions remain denied with
   `web_writes_enabled = 0`;
8. only after successful read-only validation, set
   `web_writes_enabled = 1` for the controlled write test;
9. create one Draft test DOI under an intended production namespace;
10. independently GET and verify `draft`;
11. publish explicitly and independently verify `findable`;
12. verify local persistence occurred only after Findable;
13. verify a second update preview returns `UPDATE_NOOP`.
