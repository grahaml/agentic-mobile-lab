#!/usr/bin/env bash
# One-shot Termux installer for the device-side telemetry push agent (Spec 2).
#
# Usage:
#   bash install.sh <macbuntu-ip> <device-name>
#
# - Installs Termux deps (termux-api, jq, cronie).
# - Enables crond.
# - Patches metrics_push.sh placeholders with the collector URL and device name.
# - Schedules two cron entries to fire every 30 seconds (:00 and :30).
# - Runs the script once immediately so the dashboard sees data right away.

set -u

if [ "$#" -ne 2 ]; then
    echo "usage: bash install.sh <macbuntu-ip> <device-name>" >&2
    exit 1
fi

MACBUNTU_IP="$1"
DEVICE_NAME="$2"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
METRICS_SCRIPT="$SCRIPT_DIR/metrics_push.sh"

if [ ! -f "$METRICS_SCRIPT" ]; then
    echo "error: metrics_push.sh not found at $METRICS_SCRIPT" >&2
    exit 1
fi

COLLECTOR_URL="http://${MACBUNTU_IP}:8765/metrics"

# --- Termux deps — only install if any are missing -------------------------
if command -v pkg >/dev/null 2>&1; then
    MISSING=""
    command -v jq       >/dev/null 2>&1 || MISSING="$MISSING jq"
    command -v crond    >/dev/null 2>&1 || MISSING="$MISSING cronie"
    command -v sv-enable >/dev/null 2>&1 || MISSING="$MISSING termux-services"
    if [ -n "$MISSING" ]; then
        pkg install -y $MISSING || true
    fi
else
    echo "warn: 'pkg' not found — skipping Termux dependency install" >&2
fi

# --- Enable and start crond (survives Termux restarts) ---------------------
# Try runit (termux-services) first; if the service dir is missing, fall back
# to adding crond to ~/.termux/boot/ which Termux:Boot runs on every start.
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
CROND_SV="$PREFIX/etc/runit/sv/crond"
if command -v sv-enable >/dev/null 2>&1; then
    if [ ! -d "$CROND_SV" ]; then
        mkdir -p "$CROND_SV"
        printf '#!/data/data/com.termux/files/usr/bin/sh\nexec crond -n\n' > "$CROND_SV/run"
        chmod +x "$CROND_SV/run"
    fi
    sv-enable crond 2>/dev/null || true
fi
# Termux:Boot fallback — ensures crond starts on reboot even without runit
BOOT_DIR="$HOME/.termux/boot"
BOOT_SCRIPT="$BOOT_DIR/start-agent"
mkdir -p "$BOOT_DIR"
if [ -f "$BOOT_SCRIPT" ]; then
    grep -qF 'crond' "$BOOT_SCRIPT" || echo 'pgrep crond >/dev/null || crond' >> "$BOOT_SCRIPT"
else
    printf '#!/data/data/com.termux/files/usr/bin/bash\npgrep crond >/dev/null || crond\n' > "$BOOT_SCRIPT"
    chmod +x "$BOOT_SCRIPT"
fi
# Start immediately if not already running
pgrep crond >/dev/null 2>&1 || crond 2>/dev/null || true

# --- Patch placeholders in-place -------------------------------------------
# Use | as the sed delimiter so URLs with / don't need escaping.
sed -i \
    -e "s|__COLLECTOR_URL__|${COLLECTOR_URL}|g" \
    -e "s|__DEVICE_NAME__|${DEVICE_NAME}|g" \
    "$METRICS_SCRIPT"

chmod +x "$METRICS_SCRIPT"

# --- Cron entries (idempotent: strip and rewrite every ~15 seconds) --------
CLEAN=$(crontab -l 2>/dev/null | grep -vF "$METRICS_SCRIPT" || true)
printf '%s\n%s\n%s\n%s\n%s\n' \
    "$CLEAN" \
    "* * * * * $METRICS_SCRIPT" \
    "* * * * * sleep 15 && $METRICS_SCRIPT" \
    "* * * * * sleep 30 && $METRICS_SCRIPT" \
    "* * * * * sleep 45 && $METRICS_SCRIPT" \
    | sed '/./,$!d' | crontab -

# --- Fire once immediately so the dashboard sees data fast -----------------
bash "$METRICS_SCRIPT" || true

echo "installed: pushing to $COLLECTOR_URL as device '$DEVICE_NAME'"
