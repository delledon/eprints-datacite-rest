#!/usr/bin/env python3
from pathlib import Path
import re, sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
exclude_names = {'LICENSE', 'SHA256SUMS'}
exclude_paths = {
    Path('docs/PROVENANCE.md'),
    Path('t/provenance/UPSTREAM_README.md'),
    Path('t/provenance/DataCiteDoi.epmi'),
    Path('docs/SOURCE_COMPARISON.md'),
    Path('tools/prepublish-check.py'),
}

literal_credential = re.compile(
    r'''(?ix)\b(pass(?:word)?|api[_-]?key|secret|token)\w*\s*(?:=>|=)\s*(["'])(?=\S)(.+?)\2'''
)
production = re.compile(
    r'(?i)10\.6093|crui\.unina|\bfedoa\b|\brmoa\b|\bunina\b|retimedievali|datacite-(?:fedoa|rmoa)\.key'
)
private_key = re.compile(r'BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY')

hits = {'embedded_credentials': [], 'production_tokens': [], 'private_keys': []}

for path in root.rglob('*'):
    if not path.is_file() or '.git' in path.parts or path.name in exclude_names:
        continue
    rel = path.relative_to(root)
    try:
        text = path.read_text(errors='replace')
    except Exception:
        continue
    for lineno, line in enumerate(text.splitlines(), 1):
        if literal_credential.search(line):
            hits['embedded_credentials'].append((rel, lineno))
        if rel not in exclude_paths and production.search(line):
            hits['production_tokens'].append((rel, lineno))
        if private_key.search(line):
            hits['private_keys'].append((rel, lineno))

for label, title in [
    ('embedded_credentials', 'LIKELY EMBEDDED CREDENTIALS'),
    ('production_tokens', 'PRODUCTION/INSTITUTION TOKENS'),
    ('private_keys', 'PRIVATE KEY MATERIAL'),
]:
    print(f'===== {title} =====')
    if hits[label]:
        for rel, lineno in hits[label]:
            print(f'{rel}:{lineno}')
    else:
        print('NONE')
    print()

bad = sum(len(v) for v in hits.values())
print(f'PREPUBLICATION_SCAN_HITS={bad}')
sys.exit(1 if bad else 0)
