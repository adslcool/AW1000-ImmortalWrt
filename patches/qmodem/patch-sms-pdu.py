#!/usr/bin/env python3
from pathlib import Path
import sys

roots = [Path("feeds/qmodem"), Path("package/feeds/qmodem")]
matches = []
for root in roots:
    if root.exists():
        matches.extend(
            root.glob(
                "**/luci-app-qmodem-next/htdocs/luci-static/resources/qmodem/sms-pdu.js"
            )
        )

seen = set()
targets = []
for p in matches:
    try:
        rp = p.resolve()
    except OSError:
        rp = p
    key = str(rp)
    if key not in seen and rp.is_file():
        seen.add(key)
        targets.append(rp)

if not targets:
    print("::warning::QModem sms-pdu.js not found; optional AW1000 SMS compatibility patch skipped")
    sys.exit(0)

replacement = """// AW1000_SMS_RECIPIENT_NORMALIZE
// Normalize recipient before semi-octet TP-DA encoding.
// +86 138-0013-8000 -> 8613800138000 with international TON/NPI 0x91
// 13800138000       -> 13800138000 with national/unknown TON/NPI 0x81
var rawReceiver = String(message.receiver || '').replace(/[\\s()\-]/g, '');
if (/^0086\d+$/.test(rawReceiver))
    rawReceiver = '+' + rawReceiver.slice(2);
else if (/^1\d{10}$/.test(rawReceiver))
    rawReceiver = '+86' + rawReceiver;

var isInternational = rawReceiver.charAt(0) === '+';
var normalizedReceiver = isInternational ? rawReceiver.slice(1) : rawReceiver;

if (!normalizedReceiver || !/^\d+$/.test(normalizedReceiver))
    throw new Error('Invalid SMS recipient number');

var receiverSize = ('00' + normalizedReceiver.length.toString(16)).slice(-2);
var receiver = pduParser.swapNibbles(normalizedReceiver);
var receiverType = isInternational ? '91' : '81';

pdu += receiverSize + receiverType + receiver;"""

patched = 0
upstream_as_is = 0

for target in targets:
    text = target.read_text(encoding="utf-8")

    if "AW1000_SMS_RECIPIENT_NORMALIZE" in text:
        print(f"SMS recipient patch already present: {target}")
        continue

    lines = text.splitlines(keepends=True)
    start = receiver_line = type_line = end = None

    for i, line in enumerate(lines):
        compact = "".join(line.split())

        if start is None:
            if (
                "varreceiverSize=" in compact
                and "message.receiver" in compact
                and "toString(16)" in compact
            ):
                start = i
            continue

        if i > start + 16:
            break

        if "pduParser.swapNibbles(message.receiver)" in compact:
            receiver_line = i

        if "varreceiverType=" in compact:
            type_line = i

        if (
            "pdu+=" in compact
            and "receiverSize" in compact
            and "receiverType" in compact
            and "receiver" in compact
        ):
            end = i
            break

    if None not in (start, receiver_line, type_line, end):
        indent = lines[start][: len(lines[start]) - len(lines[start].lstrip())]
        repl_lines = [
            ((indent + line) if line else "") + "\n"
            for line in replacement.splitlines()
        ]
        lines[start:end + 1] = repl_lines
        target.write_text("".join(lines), encoding="utf-8")
        patched += 1
        print(f"Patched QModem SMS recipient encoding: {target}")
    else:
        # Upstream may already have fixed/reworked this logic. Source drift
        # must not abort a multi-hour router build.
        upstream_as_is += 1
        print(
            f"::warning::QModem SMS PDU code no longer matches the known legacy "
            f"layout; using upstream implementation unchanged: {target}"
        )

print(
    f"QModem SMS patch summary: patched={patched}, "
    f"upstream-as-is={upstream_as_is}"
)
