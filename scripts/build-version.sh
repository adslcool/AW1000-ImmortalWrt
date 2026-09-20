#!/usr/bin/env bash
# Merge the resolved release identity BEFORE make defconfig.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWRT_DIR="${1:-immortalwrt}"
: "${IMMORTALWRT_VERSION:?Run the official release resolver first}"
: "${IMMORTALWRT_REVISION:?Official version.buildinfo revision is required}"
export IMMORTALWRT_VERSION IMMORTALWRT_REVISION
python3 - "$OWRT_DIR/.config" "$REPO_ROOT/config/version.config" <<'PY'
import os, re, sys
from pathlib import Path
version, revision = os.environ['IMMORTALWRT_VERSION'], os.environ['IMMORTALWRT_REVISION']
if not re.fullmatch(r'25\.12\.[0-9]+', version):
    raise SystemExit('Expected an official 25.12.X release')
if not re.fullmatch(r'r[0-9]+-[0-9a-f]{7,40}', revision):
    raise SystemExit('Invalid official release revision')
cfg, template = map(Path, sys.argv[1:])
addition = template.read_text().replace('@@IMMORTALWRT_VERSION@@', version).replace('@@IMMORTALWRT_REVISION@@', revision)
keys = set(re.findall(r'^(CONFIG_[A-Z0-9_]+)=', addition, re.M))
lines = [line for line in cfg.read_text().splitlines()
         if line.split('=', 1)[0] not in keys and line not in {f'# {key} is not set' for key in keys}]
cfg.write_text('\n'.join(lines) + '\n' + addition)
print(f'Merged release identity: {version} / {revision}, IMAGEOPT=y, VERSIONOPT=y')
PY
