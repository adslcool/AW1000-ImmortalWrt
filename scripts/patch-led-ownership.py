#!/usr/bin/env python3
"""Let the role controller own 5G RGB; keep upstream CSQ/Wi-Fi/Internet/night UI."""
from pathlib import Path
import sys

root = Path(sys.argv[1])
path = root / 'root/usr/bin/led-status-check.sh'
text = path.read_text()
marker = '# AW1000_ROLE_LED_OWNER'
if marker not in text:
    anchor = 'set_color() {'
    if text.count(anchor) != 1 or 'local PREFIX="$1"' not in text or '/sys/class/leds/${CH}:${PREFIX}' not in text:
        raise SystemExit('Unknown ledstatus writer layout: review package source before building')
    guard = '''
    # AW1000_ROLE_LED_OWNER: skip ALL upstream 5G color/heartbeat writes.
    if [ "$1" = "5g" ] && [ "$(uci -q get aw1000-5g-role-led.main.enabled)" != "0" ]; then
        return 0
    fi
'''
    text = text.replace(anchor, anchor + guard, 1)
    path.write_text(text)
# Night mode is cooperative: publish its state BEFORE touching the LEDs.
night = root / 'root/usr/bin/led-night-mode.sh'
text = night.read_text()
marker = '# AW1000_NIGHT_FLAG_FIRST'
if marker not in text:
    anchor = 'night_on() {'
    if text.count(anchor) != 1 or 'NIGHT_ACTIVE_FLAG=' not in text:
        raise SystemExit('Unknown night-mode layout: review package source before building')
    text = text.replace(anchor, anchor + '\n    # AW1000_NIGHT_FLAG_FIRST\n    touch "$NIGHT_ACTIVE_FLAG"\n', 1)
    night.write_text(text)
print('Patched ledstatus 5G ownership and cooperative night mode')
