#!/usr/bin/env bash
set -euo pipefail
OWRT_DIR="${1:-immortalwrt}"
cd "$OWRT_DIR"

# We support/control RG500Q-EA but intentionally do NOT embed Quectel modem
# firmware payloads.  Fail CI if an obvious RG500 firmware file/version string
# ends up inside a produced root filesystem.
found=0
while IFS= read -r -d '' f; do
    echo "ERROR: unexpected RG500 modem firmware-like file in rootfs: $f" >&2
    found=1
done < <(find build_dir -type f \
    \( -iname '*RG500Q*' -o -iname '*RG500QEAAAR11A06M4G*' \) -path '*/root-*/*' -print0 2>/dev/null || true)

if [ "$found" -ne 0 ]; then
    exit 1
fi

echo 'OK: no RG500Q/RG500Q-EA modem firmware image detected in built rootfs.'
