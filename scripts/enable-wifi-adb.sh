#!/bin/bash
# Enable WiFi ADB on a single USB-connected fleet device.
#
# Plug the device in via USB, run this script with its fleet name, then unplug.
# WiFi ADB does not persist across reboots on unrooted devices — re-run when needed.
#
# Usage:
#   ./enable-wifi-adb.sh <device-name>   # e.g. s8, ph1, s20fe
#
# The device name must match an entry in telemetry/fleet.yaml.

set -euo pipefail

if [ "${1:-}" = "" ]; then
    echo "usage: $(basename "$0") <device-name>" >&2
    echo "  device-name must match an entry in telemetry/fleet.yaml" >&2
    exit 1
fi

DEVICE_NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLEET_YAML="$SCRIPT_DIR/../telemetry/fleet.yaml"

# --- Look up the fleet IP for this device -----------------------------------
DEVICE_IP=$(python3 -c "
import yaml, sys
with open('$FLEET_YAML') as f:
    cfg = yaml.safe_load(f) or {}
for tier_body in (cfg.get('tiers') or {}).values():
    for d in (tier_body or {}).get('devices', []) or []:
        if d.get('name') == '$DEVICE_NAME':
            url = d.get('base_url', '')
            print(url.split('//', 1)[-1].split(':', 1)[0])
            sys.exit(0)
sys.exit(1)
" 2>/dev/null) || { echo "ERROR: '$DEVICE_NAME' not found in fleet.yaml" >&2; exit 1; }

# --- Require exactly one USB device -----------------------------------------
# grep -v ':' filters out WiFi ADB entries (ip:port). The || true prevents
# set -e from killing the script when no USB devices are present.
USB_DEVICES=$(adb devices | awk '/\tdevice$/ && !/^List/ {print $1}' | grep -v ':' || true)
USB_COUNT=$(echo "$USB_DEVICES" | grep -c . || true)

if [ "$USB_COUNT" -eq 0 ]; then
    echo "ERROR: No USB device found in 'adb devices' output:" >&2
    adb devices >&2
    echo "" >&2
    echo "  - Is $DEVICE_NAME plugged in via USB?" >&2
    echo "  - Has USB debugging been authorized on the device? (check for a dialog on screen)" >&2
    exit 1
elif [ "$USB_COUNT" -gt 1 ]; then
    echo "ERROR: Multiple USB devices connected. Plug in only one device at a time." >&2
    adb devices
    exit 1
fi

USB_SERIAL="$USB_DEVICES"
echo "Found USB device: $USB_SERIAL"
echo "Enabling WiFi ADB on $DEVICE_NAME ($DEVICE_IP)..."

# --- Enable tcpip mode ------------------------------------------------------
adb -s "$USB_SERIAL" tcpip 5555
sleep 1

# --- Connect wirelessly -----------------------------------------------------
CONNECT_OUT=$(adb connect "$DEVICE_IP:5555" 2>&1)
echo "$CONNECT_OUT"

if echo "$CONNECT_OUT" | grep -q "connected"; then
    echo "OK — $DEVICE_NAME is now reachable at $DEVICE_IP:5555"
else
    echo "ERROR: connected tcpip but failed to reach $DEVICE_IP:5555 — check that the device is on the lab WiFi." >&2
    exit 1
fi
