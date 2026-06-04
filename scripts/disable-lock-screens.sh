#!/bin/bash
# One-shot: disable lock screens fleet-wide via WiFi ADB.
#
# Tries `locksettings set-disabled true` on every device in fleet.yaml.
# Works reliably on rooted/non-Knox devices. Knox-locked Samsungs will fail —
# wake-fleet-displays.sh handles those via PIN input at wake time instead.
#
# Requires WiFi ADB to be active on all devices first (run enable-wifi-adb.sh
# per device if needed). Reads DEVICE_PIN from scripts/.env.
#
# Usage:
#   ./disable-lock-screens.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLEET_YAML="$SCRIPT_DIR/../telemetry/fleet.yaml"
ENV_FILE="$SCRIPT_DIR/.env"
ADB_PORT=5555

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found. Copy scripts/.env.example to scripts/.env and set DEVICE_PIN." >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

if [ -z "${DEVICE_PIN:-}" ]; then
    echo "ERROR: DEVICE_PIN is not set in $ENV_FILE." >&2
    exit 1
fi

# --- Parse fleet IPs from fleet.yaml ----------------------------------------
DEVICES=$(python3 -c "
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

echo "Disabling lock screens fleet-wide..."
echo ""

OK=0; FAILED=0; SKIPPED=0

while IFS=$'\t' read -r NAME IP; do
    [ -z "$NAME" ] && continue
    printf "  %-12s (%s) ... " "$NAME" "$IP"

    CONNECT_OUT=$(adb connect "$IP:$ADB_PORT" 2>&1)
    if ! echo "$CONNECT_OUT" | grep -q "connected"; then
        echo "SKIPPED (WiFi ADB unreachable — run enable-wifi-adb.sh first)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    SERIAL="$IP:$ADB_PORT"

    # Clear the PIN first, then disable the lock screen.
    # </dev/null prevents adb shell from consuming the while loop's stdin.
    if adb -s "$SERIAL" shell locksettings clear --old "$DEVICE_PIN" </dev/null >/dev/null 2>&1 \
    && adb -s "$SERIAL" shell locksettings set-disabled true </dev/null >/dev/null 2>&1; then
        echo "OK"
        OK=$((OK + 1))
    else
        echo "FAILED (Knox likely blocking — wake script will use PIN fallback)"
        FAILED=$((FAILED + 1))
    fi
done <<< "$DEVICES"

echo ""
echo "Done — disabled: $OK  Knox-blocked: $FAILED  unreachable: $SKIPPED"
[ "$FAILED" -gt 0 ] && echo "Knox-blocked devices will be unlocked via PIN input in wake-fleet-displays.sh."
