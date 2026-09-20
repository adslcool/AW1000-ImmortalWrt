#!/usr/bin/env python3
"""Validate actual Kconfig and produced rootfs/manifest, not source comments."""
import os, re, sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
mode = sys.argv[2] if len(sys.argv) > 2 else 'config'
version = os.environ.get('IMMORTALWRT_VERSION', '')
revision = os.environ.get('IMMORTALWRT_REVISION', '')
def require(ok, message):
    if not ok:
        raise SystemExit('::error::' + message)
require(re.fullmatch(r'25\.12\.[0-9]+', version), 'Missing/invalid resolved release version')
require(re.fullmatch(r'r[0-9]+-[0-9a-f]{7,40}', revision), 'Missing/invalid official revision')
config = {}
for line in (root / '.config').read_text().splitlines():
    if line.startswith('CONFIG_') and '=' in line:
        key, val = line.split('=', 1)
        config[key] = val
for key, expected in {
    'CONFIG_IMAGEOPT': 'y', 'CONFIG_VERSIONOPT': 'y',
    'CONFIG_VERSION_NUMBER': f'"{version}"',
    'CONFIG_VERSION_CODE': f'"{revision}"',
    'CONFIG_VERSION_REPO': f'"https://downloads.immortalwrt.org/releases/{version}"',
    'CONFIG_PACKAGE_luci-app-openclash': 'y',
}.items():
    require(config.get(key) == expected, f'{key} must be {expected} after make defconfig; got {config.get(key)!r}')
forbidden = {'xray-core','luci-app-ssr-plus','luci-app-passwall','luci-app-passwall2','mihomo'}
for pkg in forbidden:
    require(config.get('CONFIG_PACKAGE_' + pkg) not in {'y', 'm'}, f'Forbidden selected component: {pkg}')
if mode == 'image':
    # For a single-device firmware build this must find the installed root tree.
    releases = list((root / 'build_dir').glob('target-*/root-*/etc/openwrt_release'))
    require(releases, 'No installed rootfs /etc/openwrt_release was produced')
    for path in releases:
        text = path.read_text()
        def release_field(name):
            match = re.search(rf"^{re.escape(name)}='([^']*)'$", text, re.M)
            return match.group(1) if match else None
        actual_release = release_field('DISTRIB_RELEASE')
        actual_revision = release_field('DISTRIB_REVISION')
        require(actual_release == version,
                f'Wrong release in {path}: expected {version!r}, got {actual_release!r}')
        require(actual_revision == revision,
                f'Wrong source revision in {path}: expected {revision!r}, got {actual_revision!r}')
        require('SNAPSHOT' not in text, f'SNAPSHOT identity in {path}')
    target = root / 'bin/targets/qualcommax/ipq807x'
    manifests = list(target.glob('*arcadyan_aw1000*.manifest'))
    require(manifests, 'AW1000 image package manifest missing')
    for path in manifests:
        packages = {line.split()[0] for line in path.read_text().splitlines() if line.strip()}
        require('luci-app-openclash' in packages, 'OpenClash absent from image manifest')
        require(not packages & forbidden, 'Forbidden packages in image: ' + ', '.join(sorted(packages & forbidden)))
    for suffix in ('-sysupgrade.bin', '-factory.ubi', '-initramfs-uImage.itb'):
        require(any(target.glob('*arcadyan_aw1000*' + suffix)), f'Missing AW1000 artifact {suffix}')
else:
    require(mode == 'config', 'Unknown verification mode: ' + mode)
print(f'PASS: {mode} validation for ImmortalWrt {version} / {revision}')
