# Validation matrix

Before a stable release, test on a non-production EPrints archive.

- plugin classes load;
- `epadmin test <archive>` passes;
- phrase XML validates;
- generated XML validates against Metadata Schema 4.7;
- CLI write call => `BLOCK_UNAUTHORISED_USER`;
- missing or false `web_writes_enabled` => all Staff Screen write actions denied;
- preflight and preview actions remain usable while web writes are disabled;
- `web_writes_enabled = 1` alone is insufficient without an allowed current user;
- disallowed web user cannot write;
- mint preview => no write;
- Draft creation => exactly one POST, final state `draft`;
- publication => exactly one PUT, final state `findable`;
- local DOI remains empty before Findable;
- existing external DOI => block;
- wrong managed eprintid => block;
- client mismatch => block;
- broken managed historical DOI (404) => manual-review block;
- freshly synchronized modern DOI => `UPDATE_NOOP`;
- permitted URL migration => URL-only PUT then `UPDATE_NOOP`.
