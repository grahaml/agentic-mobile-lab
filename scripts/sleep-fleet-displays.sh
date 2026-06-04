#!/bin/bash
# Put fleet rack displays to sleep.
#
# Sends KEYCODE_SLEEP to each device — screen off, tmux session keeps running
# in the background so wake-fleet-displays.sh can bring it back instantly.
#
# Usage:
#   ./sleep-fleet-displays.sh            # sleep all WiFi-ADB-reachable devices
#   ./sleep-fleet-displays.sh <ip>       # sleep a single device by IP

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLEET_YAML="$SCRIPT_DIR/../telemetry/fleet.yaml"
ADB_PORT=5555
TARGET_IP="${1:-}"

ALL_DEVICES=$(python3 -c "
import yaml, sys
with open('$FLEET_YAML') as f:
    cfg = yaml.safe_load(f) or {}
seen = set()
for tier_body in (cfg.get('tiers') or {}).values():
    for d in (tier_body or {}).get('devices', []) or []:
        name = d.get('name')
        if not name or name in seen:
            continue
        seen.add(name)
        url = d.get('base_url', '')
        ip = url.split('//', 1)[-1].split(':', 1)[0]
        print(f'{name}\t{ip}')
")

if [ -n "$TARGET_IP" ]; then
    DEVICES=$(echo "$ALL_DEVICES" | awk -v ip="$TARGET_IP" -F'\t' '$2 == ip')
    [ -z "$DEVICES" ] && DEVICES="target	$TARGET_IP"
else
    DEVICES="$ALL_DEVICES"
fi

echo "Sleeping fleet displays..."
echo ""
SKIPPED=0

while IFS=$'\t' read -r NAME IP; do
    [ -z "$NAME" ] && continue
    printf "  %-12s (%s) ... " "$NAME" "$IP"

    CONNECT_OUT=$(adb connect "$IP:$ADB_PORT" 2>&1)
    if echo "$CONNECT_OUT" | grep -q "connected"; then
        adb -s "$IP:$ADB_PORT" shell input keyevent KEYCODE_SLEEP </dev/null 2>/dev/null
        echo "OK"
    else
        echo "SKIPPED (WiFi ADB unreachable)"
        SKIPPED=$((SKIPPED + 1))
    fi
done <<< "$DEVICES"

echo ""
[ "$SKIPPED" -gt 0 ] \
    && echo "$SKIPPED device(s) unreachable." \
    || echo "All displays sleeping."
