#!/bin/bash

# Configuration
BACKUP_BASE="/media/grahaml/easystore1/BACKUPS/PHONE"
DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Get list of connected devices
DEVICES=$(adb devices | grep -w "device" | awk '{print $1}')

if [ -z "$DEVICES" ]; then
    echo "❌ No devices connected via ADB."
    exit 1
fi

for SERIAL in $DEVICES; do
    # Get device model for naming
    MODEL=$(adb -s "$SERIAL" shell getprop ro.product.model | tr -d '\r' | sed 's/ /_/g')
    BACKUP_DIR="$BACKUP_BASE/${MODEL}_${SERIAL}_$DATE"
    
    echo "📱 Starting backup for $MODEL ($SERIAL)..."
    echo "📂 Destination: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # List of directories to pull
    TARGETS=("DCIM" "Pictures" "Documents" "Download" "WhatsApp" "Music" "Movies" "Termux")

    for TARGET in "${TARGETS[@]}"; do
        echo "   📥 Pulling /sdcard/$TARGET..."
        # Check if directory exists before pulling to avoid errors
        if adb -s "$SERIAL" shell ls -d "/sdcard/$TARGET" >/dev/null 2>&1; then
            adb -s "$SERIAL" pull "/sdcard/$TARGET" "$BACKUP_DIR/" 2>>"$BACKUP_DIR/backup_errors.log"
        else
            echo "   ⚠️  /sdcard/$TARGET not found, skipping."
        fi
    done

    echo "✅ Backup complete for $MODEL ($SERIAL)."
    echo "-------------------------------------------"
done

echo "🎉 All device backups finished. Logs (if any) are in their respective folders."
