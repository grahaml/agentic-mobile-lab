#!/bin/bash

# ==========================================
# 🔄 Mobile Bridge Refresher
# ==========================================
# Automatically detects the current IP of a connected 
# phone via ADB and updates the Kubernetes bridge.
# ==========================================

set -e

# Configuration
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SERVICE_ROLE=${1:-"scout"}
DEVICE_ID=${2:-$(adb shell getprop ro.product.model | tr -d '\r' | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')}

echo "🔍 Detecting IP for device: $DEVICE_ID (Role: $SERVICE_ROLE)..."

# 1. Connectivity Check
if ! adb devices | grep -q "device$"; then
    echo "❌ ERROR: No device found via ADB. Please connect the phone."
    exit 1
fi

# 2. Get Phone IP
PHONE_IP=$(adb shell "ip addr show wlan0 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" | tr -d '\r')

if [ -z "$PHONE_IP" ]; then
    echo "❌ ERROR: Could not detect Phone IP. Is Wi-Fi connected?"
    exit 1
fi

echo "📶 Detected IP: $PHONE_IP"

# 3. Update the Bridge
echo "🚀 Updating Kubernetes bridge..."
"$DIR/bridge-phone.sh" "$PHONE_IP" "$SERVICE_ROLE" "$DEVICE_ID"

echo "✅ Bridge refreshed successfully!"
