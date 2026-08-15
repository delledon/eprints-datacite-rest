#!/usr/bin/env python3

from pathlib import Path
import re
import sys

path = Path(
    "lib/plugins/EPrints/Plugin/Screen/EPrint/Staff/DataCiteREST.pm"
)

text = path.read_text()

def sub_block(name):
    match = re.search(
        rf"^sub {re.escape(name)}\b.*?(?=^sub |\Z)",
        text,
        re.M | re.S,
    )

    if not match:
        print(f"{name}=MISSING")
        sys.exit(1)

    return match.group(0)


write_allows = [
    "allow_datacite_update_url_https",
    "allow_datacite_publish_findable",
    "allow_datacite_create_draft",
]

write_actions = [
    "action_datacite_update_url_https",
    "action_datacite_publish_findable",
    "action_datacite_create_draft",
]

readonly_allows = [
    "allow_datacite_preflight",
    "allow_datacite_prepare_draft",
    "allow_datacite_prepare_update_url",
    "allow_datacite_prepare_publish",
]

readonly_actions = [
    "action_datacite_preflight",
    "action_datacite_prepare_draft",
    "action_datacite_prepare_update_url",
    "action_datacite_prepare_publish",
]

ok = True

print("===== GLOBAL HELPER =====")

block = sub_block("_web_writes_enabled")
good = '"web_writes_enabled"' in block
print("GLOBAL_WEB_GATE=" + ("PASS" if good else "FAIL"))
ok &= good


print("\n===== WRITE ALLOWS =====")

for name in write_allows:
    block = sub_block(name)

    good = (
        "_current_user_allowed()" in block
        and "_web_writes_enabled()" in block
    )

    print(f"{name}={'PASS' if good else 'FAIL'}")
    ok &= good


print("\n===== WRITE ACTIONS =====")

for name in write_actions:
    block = sub_block(name)

    good = (
        "_current_user_allowed()" in block
        and "_web_writes_enabled()" in block
        and "web write denied by Screen policy" in block
    )

    print(f"{name}={'PASS' if good else 'FAIL'}")
    ok &= good


print("\n===== READ-ONLY ALLOWS =====")

for name in readonly_allows:
    block = sub_block(name)

    good = "_web_writes_enabled()" not in block

    print(f"{name}={'PASS' if good else 'FAIL'}")
    ok &= good


print("\n===== READ-ONLY ACTIONS =====")

preview_ui_actions = {
    "action_datacite_prepare_draft",
    "action_datacite_prepare_update_url",
    "action_datacite_prepare_publish",
}

for name in readonly_actions:
    block = sub_block(name)

    forbidden_write_call = re.search(
        r"->\s*(?:"
        r"create_mint_draft|"
        r"publish_mint_findable|"
        r"update_modern_url_https"
        r")\s*\(",
        block,
    )

    good = (
        "web write denied by Screen policy" not in block
        and forbidden_write_call is None
    )

    if name in preview_ui_actions:
        good = (
            good
            and "_web_writes_enabled()" in block
            and "no DataCite write action is available" in block
        )
    else:
        good = (
            good
            and "_web_writes_enabled()" not in block
        )

    print(f"{name}={'PASS' if good else 'FAIL'}")
    ok &= good


print(
    "\nWEB_WRITE_GATE_SMOKE="
    + ("OK" if ok else "FAIL")
)

sys.exit(0 if ok else 1)
