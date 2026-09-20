#!/usr/bin/env bash
set -euo pipefail

OWRT_DIR="${1:-immortalwrt}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

: "${ROOT_PASSWORD_HASH:?ROOT_PASSWORD_HASH is required}"
: "${WIFI_PASSWORD:?WIFI_PASSWORD is required}"
: "${HOSTNAME:=AW1000}"
: "${SSID_2G:=AW1000-2G}"
: "${SSID_5G:=AW1000-5G}"
: "${IMMORTALWRT_VERSION:?IMMORTALWRT_VERSION is required}"
: "${IMMORTALWRT_REVISION:?IMMORTALWRT_REVISION is required}"

# Fixed product defaults requested for this firmware.
LAN_IP='192.168.8.1'
LAN_NETMASK='255.255.255.0'
DHCP_START_OFFSET='10'
DHCP_LIMIT='90'          # 192.168.8.10 - 192.168.8.99 inclusive
WAN_PROTO='dhcp'
WIFI_COUNTRY='CN'
ZONENAME='Asia/Shanghai'
TIMEZONE='CST-8'

if [ ! -d "$OWRT_DIR" ]; then
    echo "OpenWrt source directory not found: $OWRT_DIR" >&2
    exit 1
fi

cd "$OWRT_DIR"

# ------------------------------------------------------------------
# Official feeds are pinned to the exact commits published with the resolved
# stable release. Do not mix a stable main source with moving feed HEADs.
# ------------------------------------------------------------------
OFFICIAL_FEEDS_LOCK="$REPO_ROOT/IMMORTALWRT_FEEDS_RELEASE.txt"
if [ ! -s "$OFFICIAL_FEEDS_LOCK" ]; then
    echo "Official release feed lock not found: $OFFICIAL_FEEDS_LOCK" >&2
    exit 1
fi
cp "$OFFICIAL_FEEDS_LOCK" feeds.conf.default

# ------------------------------------------------------------------
# Third-party packages: verify/materialize the repository-local Vendor snapshot.
# ------------------------------------------------------------------
VENDOR_LOCK="$REPO_ROOT/vendor/VENDOR_COMMITS.txt"
VENDOR_ROOT="$(bash "$REPO_ROOT/scripts/materialize-vendor.sh" "$REPO_ROOT")"

# A normal build must not silently move third-party packages to upstream HEAD.
for name in QModem luci-theme-argon luci-app-aw1k-led luci-app-openclash; do
    if [ ! -d "$VENDOR_ROOT/$name" ] || ! find "$VENDOR_ROOT/$name" -type f -name Makefile -print -quit | grep -q .; then
        echo "::error::Vendor snapshot missing: $name. Run Actions -> Sync Third-Party Vendor Sources once, then rebuild." >&2
        exit 1
    fi
    if ! grep -Eq "^${name}[[:space:]]+[0-9a-f]{40}[[:space:]]+https://" "$VENDOR_LOCK"; then
        echo "::error::Vendor commit record missing for $name; refresh Vendor snapshots." >&2
        exit 1
    fi
done
rm -rf .aw1000-vendor
mkdir -p .aw1000-vendor
cp -a "$VENDOR_ROOT/QModem" .aw1000-vendor/QModem
echo "src-link qmodem $(pwd)/.aw1000-vendor/QModem" >> feeds.conf.default
THIRD_PARTY_MODE='local-vendor'

./scripts/feeds update -a
./scripts/feeds install -a

echo "Applying repository-local AW1000 QModem SMS compatibility patch..."
python3 "$REPO_ROOT/patches/qmodem/patch-sms-pdu.py"

rm -rf package/custom
mkdir -p package/custom

cp -a "$VENDOR_ROOT/luci-theme-argon" package/custom/luci-theme-argon
cp -a "$VENDOR_ROOT/luci-app-aw1k-led" package/custom/luci-app-aw1k-led
cp -a "$VENDOR_ROOT/luci-app-openclash" package/custom/luci-app-openclash
{
    echo "ImmortalWrt $(git rev-parse HEAD)"
    echo "Third-party mode: $THIRD_PARTY_MODE"
    cat "$VENDOR_LOCK"
} > "$REPO_ROOT/CUSTOM_PACKAGE_COMMITS.txt"

python3 "$REPO_ROOT/scripts/patch-led-ownership.py" package/custom/luci-app-aw1k-led

rm -rf files
mkdir -p files
cp -a "$REPO_ROOT/files-template/." files/

export ROOT_PASSWORD_HASH WIFI_PASSWORD HOSTNAME SSID_2G SSID_5G LAN_IP LAN_NETMASK DHCP_START_OFFSET DHCP_LIMIT WAN_PROTO WIFI_COUNTRY ZONENAME TIMEZONE

python3 - <<'PY2'
from pathlib import Path
import os, shlex
mapping = {
    '@@ROOT_PASSWORD_HASH@@': os.environ['ROOT_PASSWORD_HASH'],
    '@@WIFI_PASSWORD@@': os.environ['WIFI_PASSWORD'],
    '@@HOSTNAME@@': os.environ['HOSTNAME'],
    '@@SSID_2G@@': os.environ['SSID_2G'],
    '@@SSID_5G@@': os.environ['SSID_5G'],
    '@@LAN_IP@@': os.environ['LAN_IP'],
    '@@LAN_NETMASK@@': os.environ['LAN_NETMASK'],
    '@@DHCP_START_OFFSET@@': os.environ['DHCP_START_OFFSET'],
    '@@DHCP_LIMIT@@': os.environ['DHCP_LIMIT'],
    '@@WAN_PROTO@@': os.environ['WAN_PROTO'],
    '@@WIFI_COUNTRY@@': os.environ['WIFI_COUNTRY'],
    '@@ZONENAME@@': os.environ['ZONENAME'],
    '@@TIMEZONE@@': os.environ['TIMEZONE'],
}
for p in Path('files').rglob('*'):
    if not p.is_file():
        continue
    try:
        s = p.read_text()
    except UnicodeDecodeError:
        continue
    for k, v in mapping.items():
        s = s.replace("'" + k + "'", shlex.quote(v))
    p.write_text(s)
PY2

chmod +x files/etc/uci-defaults/99-aw1000-custom
chmod +x files/etc/uci-defaults/99-aw1000-led-fix
chmod +x files/usr/sbin/aw1000-led-status
chmod +x files/usr/sbin/aw1000-sms-diag
chmod +x files/usr/sbin/aw1000-failover
chmod +x files/etc/init.d/aw1000-failover
chmod +x files/usr/sbin/aw1000-5g-role-led
chmod +x files/etc/init.d/aw1000-5g-role-led
chmod +x files/etc/hotplug.d/iface/90-aw1000-cellular-firewall
chmod +x files/etc/hotplug.d/iface/95-aw1000-failover

# Never carry the old proxy feed/package into this build.
rm -rf package/custom/helloworld

# OpenClash must ship without any pre-bundled Mihomo/Clash core binary.
# The upstream luci-app-openclash package downloads the appropriate core at runtime.
if find package/custom/luci-app-openclash -type f -print0 2>/dev/null \
   | xargs -0 -r file 2>/dev/null \
   | grep -E 'ELF .* executable|ELF .* shared object' \
   | grep -Ei '/(core|mihomo|clash[^/]*)($|:)'; then
    echo "::error::An executable proxy core appears to be embedded in the OpenClash package source." >&2
    exit 1
fi

cp "$REPO_ROOT/config/aw1000.config" .config
bash "$REPO_ROOT/scripts/build-version.sh" "$PWD"
make defconfig
bash "$REPO_ROOT/scripts/check-release.sh" "$PWD" config

# Verify the actual Kconfig result instead of guessing package availability from
# Makefile text. Macro-generated packages (for example AW1000 ipq-wifi board
# data) are correctly handled by make defconfig.
REQUIRED_CONFIGS=(
    CONFIG_PACKAGE_qmodem
    CONFIG_PACKAGE_luci-app-qmodem-next
    CONFIG_PACKAGE_qmodem-smsd
    CONFIG_PACKAGE_sms-forwarder-next
    CONFIG_PACKAGE_kmod-qmi_wwan_q
    CONFIG_PACKAGE_kmod-usb-wdm
    CONFIG_PACKAGE_kmod-usb-acm
    CONFIG_PACKAGE_kmod-usb-serial-qualcomm
    CONFIG_PACKAGE_kmod-usb-serial-wwan
    CONFIG_PACKAGE_kmod-usb-net-qmi-wwan
    CONFIG_PACKAGE_kmod-ath11k
    CONFIG_PACKAGE_ath11k-firmware-ipq8074
    CONFIG_PACKAGE_ipq-wifi-arcadyan_aw1000
    CONFIG_PACKAGE_ppp
    CONFIG_PACKAGE_ppp-mod-pppoe
    CONFIG_PACKAGE_luci-proto-ppp
)

missing=0
for cfg in "${REQUIRED_CONFIGS[@]}"; do
    if ! grep -q "^${cfg}=y$" .config; then
        echo "::error::Required build option was not selected/available after make defconfig: ${cfg}"
        missing=1
    fi
done
[ "$missing" -eq 0 ] || exit 1

FORBIDDEN_CONFIGS=(
    CONFIG_PACKAGE_luci-app-ssr-plus
    CONFIG_PACKAGE_xray-core
    CONFIG_PACKAGE_luci-app-passwall
    CONFIG_PACKAGE_luci-app-passwall2
    CONFIG_PACKAGE_mihomo
)
for cfg in "${FORBIDDEN_CONFIGS[@]}"; do
    if grep -Eq "^${cfg}=(y|m)$" .config; then
        echo "::error::Forbidden package selected: ${cfg}" >&2
        exit 1
    fi
done
if ! grep -q "^CONFIG_VERSION_NUMBER=\"${IMMORTALWRT_VERSION}\"$" .config; then
    echo "::error::Stable release version stamp missing from final .config" >&2
    exit 1
fi

# Automatically enable every available Simplified-Chinese translation package
# corresponding to selected LuCI apps/protocols.
mapfile -t LUCI_SELECTED < <(
    sed -n 's/^CONFIG_PACKAGE_\(luci-app-[^=]*\|luci-proto-[^=]*\)=y$/\1/p' .config | sort -u
)

ZH_ADDED=()
for pkg in "${LUCI_SELECTED[@]}"; do
    case "$pkg" in
        luci-app-*) lang="luci-i18n-${pkg#luci-app-}-zh-cn" ;;
        luci-proto-*) lang="luci-i18n-proto-${pkg#luci-proto-}-zh-cn" ;;
        *) continue ;;
    esac
    if grep -q "^config PACKAGE_${lang}$" tmp/.config-package.in 2>/dev/null; then
        if ! grep -q "^CONFIG_PACKAGE_${lang}=y$" .config; then
            echo "CONFIG_PACKAGE_${lang}=y" >> .config
            ZH_ADDED+=("$lang")
        fi
    fi
done

for lang in luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn; do
    if grep -q "^config PACKAGE_${lang}$" tmp/.config-package.in 2>/dev/null; then
        grep -q "^CONFIG_PACKAGE_${lang}=y$" .config || echo "CONFIG_PACKAGE_${lang}=y" >> .config
    fi
done

make defconfig
bash "$REPO_ROOT/scripts/check-release.sh" "$PWD" config

{
    echo '# Auto-selected Simplified Chinese LuCI translations'
    printf '%s\n' "${ZH_ADDED[@]}"
} > "$REPO_ROOT/AUTO_ZH_CN_PACKAGES.txt"

echo
echo '===== Fixed product defaults ====='
echo "Hostname: $HOSTNAME"
echo "2.4G SSID: $SSID_2G"
echo "5G SSID: $SSID_5G"
echo "LAN: $LAN_IP/$LAN_NETMASK"
echo 'DHCP: 192.168.8.10 - 192.168.8.99'
echo 'WAN: DHCP on physical 2.5G fifth Ethernet port'
echo 'Country: CN'
echo 'Timezone: Asia/Shanghai'
echo
echo '===== Build target ====='
grep -E '^CONFIG_TARGET_qualcommax|arcadyan_aw1000' .config || true
echo
echo '===== Selected custom packages ====='
grep -E 'CONFIG_PACKAGE_(luci-app-openclash|qmodem|luci-app-qmodem-next|luci-app-aw1k-led|luci-theme-argon|luci-app-filemanager|luci-app-zerotier|kmod-tcp-bbr|kmod-qmi_wwan_q|kmod-ath11k|ath11k-firmware-ipq8074|ipq-wifi-arcadyan_aw1000)' .config || true
echo
echo '===== Simplified Chinese LuCI translations ====='
grep '^CONFIG_PACKAGE_luci-i18n-.*-zh-cn=y$' .config || true
