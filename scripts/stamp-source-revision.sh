#!/usr/bin/env bash
# Pin OpenWrt's REVISION variable to the exact official release revision.
set -euo pipefail

OWRT_DIR="${1:-immortalwrt}"
: "${IMMORTALWRT_REVISION:?Official version.buildinfo revision is required}"

if [[ ! "$IMMORTALWRT_REVISION" =~ ^r[0-9]+-[0-9a-f]{7,40}$ ]]; then
    echo "::error::Invalid official release revision: $IMMORTALWRT_REVISION" >&2
    exit 1
fi
if [ ! -x "$OWRT_DIR/scripts/getver.sh" ]; then
    echo "::error::ImmortalWrt getver script not found: $OWRT_DIR/scripts/getver.sh" >&2
    exit 1
fi

# package/base-files substitutes DISTRIB_REVISION from make's REVISION (%R),
# not CONFIG_VERSION_CODE (%C). A single-branch clone followed by a detached
# checkout cannot discover its upstream branch reliably and getver.sh may
# otherwise emit r0+<count>-<hash>. The source-tree version file is the
# supported highest-priority input used by getver.sh.
printf '%s\n' "$IMMORTALWRT_REVISION" > "$OWRT_DIR/version"

actual_revision="$(cd "$OWRT_DIR" && ./scripts/getver.sh)"
if [ "$actual_revision" != "$IMMORTALWRT_REVISION" ]; then
    echo "::error::Failed to pin source revision: expected $IMMORTALWRT_REVISION, got $actual_revision" >&2
    exit 1
fi

echo "Pinned source revision for rootfs identity: $actual_revision"
