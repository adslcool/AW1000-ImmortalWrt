#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.github/workflows/build-version.env"
REQUESTED="${IMMORTALWRT_REQUESTED_VERSION:-auto}"
if [[ "$REQUESTED" != auto && ! "$REQUESTED" =~ ^25\.12\.[0-9]+$ ]]; then
    echo "::error::Use auto or an official 25.12.X release, for example 25.12.2" >&2
    exit 1
fi

BASE_URL="${IMMORTALWRT_DOWNLOAD_BASE:-https://downloads.immortalwrt.org}"
TARGET_PATH="${IMMORTALWRT_TARGET_PATH:-qualcommax/ipq807x}"

retry_curl() {
    curl -fsSL --retry 4 --retry-delay 2 --connect-timeout 20 "$@"
}

echo "Resolving newest official ImmortalWrt stable release supporting arcadyan_aw1000 ..."
if [ "$REQUESTED" = auto ]; then
RELEASE_INDEX="$(retry_curl "${BASE_URL}/releases/")"
mapfile -t CANDIDATES < <(
    printf '%s\n' "$RELEASE_INDEX" \
      | grep -oE '[0-9]+\.[0-9]+\.[0-9]+/' \
      | tr -d '/' \
      | sort -Vru
)

else
    CANDIDATES=("$REQUESTED")
fi

LATEST_VERSION=""
TARGET_BASE=""
for version in "${CANDIDATES[@]}"; do
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    [[ "$version" == "${IMMORTALWRT_SERIES}."* ]] || continue
    candidate="${BASE_URL}/releases/${version}/targets/${TARGET_PATH}"
    if profiles="$(retry_curl "${candidate}/profiles.json" 2>/dev/null)" \
       && python3 -c 'import json,sys; sys.exit("arcadyan_aw1000" not in json.load(sys.stdin).get("profiles", {}))' <<< "$profiles"; then
        LATEST_VERSION="$version"
        TARGET_BASE="$candidate"
        break
    fi
done

if [ -z "$LATEST_VERSION" ]; then
    echo "::error::No requested official 25.12.X stable release publishing arcadyan_aw1000 was found." >&2
    exit 1
fi

SERIES="${LATEST_VERSION%.*}"
BRANCH="openwrt-${SERIES}"
REVISION="$(retry_curl "${TARGET_BASE}/version.buildinfo" | tr -d '\r\n[:space:]')"
if ! [[ "$REVISION" =~ ^r[0-9]+-[0-9a-fA-F]{7,40}$ ]]; then
    echo "::error::Unexpected version.buildinfo for ${LATEST_VERSION}: ${REVISION}" >&2
    exit 1
fi
COMMIT_SHORT="${REVISION##*-}"

retry_curl "${TARGET_BASE}/feeds.buildinfo" > IMMORTALWRT_FEEDS_RELEASE.txt
[ -s IMMORTALWRT_FEEDS_RELEASE.txt ] || { echo "::error::feeds.buildinfo is empty"; exit 1; }
if grep -Eiq 'SNAPSHOT' IMMORTALWRT_FEEDS_RELEASE.txt; then
    echo "::error::Official release feed metadata unexpectedly contains SNAPSHOT" >&2
    exit 1
fi

python3 - <<'PYFEEDS'
from pathlib import Path
import re
lines = [x for x in Path('IMMORTALWRT_FEEDS_RELEASE.txt').read_text().splitlines() if x and not x.startswith('#')]
feeds = set()
for line in lines:
    match = re.fullmatch(r'src-git(?:-full)?\s+([\w-]+)\s+https://[^\s^]+\^[0-9a-f]{40}', line)
    if not match:
        raise SystemExit('Official feed entry is not pinned to an exact commit: ' + line)
    if match[1] in feeds:
        raise SystemExit('Duplicate official feed: ' + match[1])
    feeds.add(match[1])
if not {'packages', 'luci', 'routing', 'telephony'}.issubset(feeds):
    raise SystemExit('Required official release feeds are missing')
PYFEEDS

cat > IMMORTALWRT_RELEASE_RESOLVED.txt <<EOF
Requested version: ${REQUESTED}
AW1000 project: ${AW1000_VERSION}
ImmortalWrt stable release: ${LATEST_VERSION}
Series: ${SERIES}
Branch used to obtain release commit: ${BRANCH}
Official version.buildinfo: ${REVISION}
Release commit: ${COMMIT_SHORT}
Target: ${TARGET_PATH}
Target metadata base: ${TARGET_BASE}
Official feeds: exact commits from release feeds.buildinfo
EOF
cat IMMORTALWRT_RELEASE_RESOLVED.txt

echo "Official pinned feeds:"
cat IMMORTALWRT_FEEDS_RELEASE.txt

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "version=${LATEST_VERSION}"
        echo "aw1000_version=${AW1000_VERSION}"
        echo "series=${SERIES}"
        echo "branch=${BRANCH}"
        echo "revision=${REVISION}"
        echo "commit=${COMMIT_SHORT}"
        echo "target_base=${TARGET_BASE}"
    } >> "$GITHUB_OUTPUT"
fi
