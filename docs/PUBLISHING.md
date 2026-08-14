# Publishing to GitHub

The repository should be published as normal source files, not as a ZIP stored
inside Git.

After reviewing the tree:

```bash
git init -b main
git add .
git status
git commit -m "Initial 0.1.0-alpha release"
```

Then create an empty GitHub repository and add it as `origin`, for example:

```bash
git remote add origin git@github.com:YOUR-ORG/eprints-datacite-rest.git
git push -u origin main
```

Before the first push run:

```bash
tools/prepublish-check.sh .
perl t/classifier-smoke.pl
sha256sum -c SHA256SUMS
```

Do not add production source snapshots, API-key files or server logs to Git.
GitHub already provides automatic source ZIP/TAR downloads; release archives
should be generated from tagged source rather than committed as binaries.

## Upstream provenance verified

The production installation was verified against:

- remote: `https://github.com/eprintsug/DataCiteDoi.git`;
- commit: `bbf501f7d9cd0062d4e002ebfe51ff40847123cb`;
- working tree: clean (`git status --short` returned no output).

These details are recorded in `docs/PROVENANCE.md`.
