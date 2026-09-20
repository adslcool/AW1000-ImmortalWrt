#!/usr/bin/env bash
set -euo pipefail
OWRT_DIR="${1:-immortalwrt}"
writer="$OWRT_DIR/package/custom/luci-app-aw1k-led/root/usr/bin/led-status-check.sh"
grep -q '^    # AW1000_ROLE_LED_OWNER' "$writer"
grep -q '^    # AW1000_NIGHT_FLAG_FIRST' "$OWRT_DIR/package/custom/luci-app-aw1k-led/root/usr/bin/led-night-mode.sh"
for path in usr/sbin/aw1000-5g-role-led usr/sbin/aw1000-led-status etc/uci-defaults/99-aw1000-led-fix; do
    test -x "$OWRT_DIR/files/$path"
    sh -n "$OWRT_DIR/files/$path"
done
echo 'PASS: patched LED ownership and executable overlay scripts'
