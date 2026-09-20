#!/usr/bin/env bash
# Verify and unpack the web-upload-friendly Vendor source snapshot.
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
ARCHIVE="$REPO_ROOT/vendor/vendor-sources.tar.gz"
CHECKSUM="$REPO_ROOT/vendor/VENDOR_ARCHIVE.sha256"
DIRECT_PACKAGES="$REPO_ROOT/vendor/packages"
MATERIALIZED="$REPO_ROOT/workdir/vendor-packages"

if [ -f "$ARCHIVE" ]; then
    if [ ! -s "$CHECKSUM" ]; then
        echo "::error::Vendor archive checksum is missing: $CHECKSUM" >&2
        exit 1
    fi
    if [ "$(wc -l < "$CHECKSUM")" -ne 1 ] \
       || ! grep -Eq '^[0-9a-f]{64}  vendor-sources\.tar\.gz$' "$CHECKSUM"; then
        echo "::error::Invalid Vendor archive checksum file: $CHECKSUM" >&2
        exit 1
    fi
    (cd "$REPO_ROOT/vendor" && sha256sum -c "$(basename "$CHECKSUM")") >&2

    # Refuse path traversal, device entries and links before extraction. The
    # four pinned upstream trees currently contain regular files/directories.
    python3 - "$ARCHIVE" <<'PY'
import sys, tarfile
from pathlib import PurePosixPath

with tarfile.open(sys.argv[1], 'r:gz') as archive:
    for member in archive.getmembers():
        path = PurePosixPath(member.name)
        if (path.is_absolute() or '..' in path.parts or not path.parts
                or path.parts[0] != 'packages'
                or member.issym() or member.islnk() or member.isdev()):
            raise SystemExit(f'::error::Unsafe Vendor archive entry: {member.name}')
PY

    rm -rf "$MATERIALIZED"
    mkdir -p "$MATERIALIZED"
    tar -xzf "$ARCHIVE" --no-same-owner -C "$MATERIALIZED"
    printf '%s\n' "$MATERIALIZED/packages"
elif [ -d "$DIRECT_PACKAGES" ]; then
    # Compatibility for developers who keep unpacked snapshots locally.
    printf '%s\n' "$DIRECT_PACKAGES"
else
    echo "::error::Vendor source snapshot is missing. Expected $ARCHIVE" >&2
    exit 1
fi
