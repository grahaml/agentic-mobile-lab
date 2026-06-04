#!/bin/bash
# Bring the fleet rack display to the foreground on all devices.
#
# Wakes each device, unlocks the screen (PIN if needed), and opens Termux.
# Termux:Boot already starts the tmux session on boot; .bashrc auto-attaches.
#
# Lock screen handling:
#   - Devices where disable-lock-screens.sh succeeded: just wakes screen.
#   - Knox-locked Samsungs: wakes, dismisses keyguard, enters PIN from .env.
# Reads DEVICE_PIN from scripts/.env (optional — skips PIN step if unset).
#
# Rooted devices (moto, ph1) retain WiFi ADB across reboots.
# Unrooted Samsungs lose WiFi ADB on reboot — run enable-wifi-adb.sh first.
#
# Usage:
#   ./wake-fleet-displays.sh            # wake all WiFi-ADB-reachable devices
#   ./wake-fleet-displays.sh <ip>       # wake a single device by IP

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FLEET_YAML="$SCRIPT_DIR/../telemetry/fleet.yaml"
ENV_FILE="$SCRIPT_DIR/.env"
ADB_PORT=5555
TARGET_IP="${1:-}"

# Load PIN if available — not required, just skips PIN unlock step if missing.
DEVICE_PIN=""
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    DEVICE_PIN="${DEVICE_PIN:-}"
fi

# --- Parse fleet IPs from fleet.yaml ----------------------------------------
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

# --- Unlock + open Termux on one device -------------------------------------
wake_device() {
    local serial="$1" label="$2"

    # Wake the screen.
    # </dev/null on every adb shell call prevents it from consuming the
    # while loop's stdin and skipping remaining devices.
    adb -s "$serial" shell input keyevent KEYCODE_WAKEUP </dev/null 2>/dev/null
    sleep 0.3

    # Check if the keyguard is showing
    if adb -s "$serial" shell dumpsys window </dev/null 2>/dev/null | grep -q 'isKeyguardShowing=true'; then
        adb -s "$serial" shell wm dismiss-keyguard </dev/null 2>/dev/null
        sleep 0.5
        if [ -n "$DEVICE_PIN" ]; then
            adb -s "$serial" shell input text "$DEVICE_PIN" </dev/null 2>/dev/null
            adb -s "$serial" shell input keyevent KEYCODE_ENTER </dev/null 2>/dev/null
            sleep 0.3
        fi
    fi

    # Ensure the tmux session exists (no-op if already running).
    # start-display.sh skips attach when stdin is not a tty, so this just
    # creates the background session without grabbing the terminal.
    adb -s "$serial" shell "export PATH=/data/data/com.termux/files/usr/bin:\$PATH && bash ~/start-display.sh" </dev/null >/dev/null 2>&1 || true

    # Open Termux, then type ~/start-display.sh into the shell.
    # am start brings the existing bash window to the foreground; the typed
    # command is what actually attaches that window to the tmux session.
    if adb -s "$serial" shell am start -n com.termux/com.termux.app.TermuxActivity </dev/null >/dev/null 2>&1; then
        sleep 1
        adb -s "$serial" shell input text "/data/data/com.termux/files/home/start-display.sh" </dev/null 2>/dev/null
        adb -s "$serial" shell input keyevent KEYCODE_ENTER </dev/null 2>/dev/null
        echo "OK"
    else
        echo "FAILED (Termux not responding)"
    fi
}

# --- Main loop --------------------------------------------------------------
echo "Waking fleet displays..."
echo ""
SKIPPED=0

while IFS=$'\t' read -r NAME IP; do
    [ -z "$NAME" ] && continue
    printf "  %-12s (%s) ... " "$NAME" "$IP"

    CONNECT_OUT=$(adb connect "$IP:$ADB_PORT" 2>&1)
    if echo "$CONNECT_OUT" | grep -q "connected"; then
        wake_device "$IP:$ADB_PORT" "$NAME"
    else
        echo "SKIPPED (WiFi ADB unreachable — run enable-wifi-adb.sh first)"
        SKIPPED=$((SKIPPED + 1))
    fi
done <<< "$DEVICES"

echo ""
[ "$SKIPPED" -gt 0 ] \
    && echo "$SKIPPED device(s) unreachable. Plug in and run enable-wifi-adb.sh to restore WiFi ADB." \
    || echo "All devices woken."
