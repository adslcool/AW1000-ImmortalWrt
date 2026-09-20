#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$REPO_ROOT/scripts/verify-build.py" "${1:-immortalwrt}" "${2:-config}"
