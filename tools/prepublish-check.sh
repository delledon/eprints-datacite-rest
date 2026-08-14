#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-.}"
exec python3 "$(dirname "$0")/prepublish-check.py" "$ROOT"
