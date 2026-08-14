# Security

Do not report API keys or credentials in public issues.

High-risk defects include:

- bypass of the authenticated EPrints current-user write gate;
- credentials appearing in logs or UI;
- a DataCite write without a fresh authenticated ownership check;
- automatic retry of DOI writes;
- duplicate DOI creation despite a DOI-like external identifier;
- local DOI persistence before remote `Findable` verification.

If a key is exposed, revoke/rotate it and inspect the entire Git history.
