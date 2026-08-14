# Contributing

Changes to write paths must preserve the safety invariants documented in
`docs/SECURITY_MODEL.md`. Repository-specific policy belongs in configuration
or mapping callbacks rather than in the generic Event/Screen classes.

Before submitting a change, test at minimum:

- `epadmin test`;
- CLI write denial;
- no-op update behavior;
- duplicate DOI barriers;
- DataCite 4.7 XML validation.
