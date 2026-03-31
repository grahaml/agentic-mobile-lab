#!/bin/bash

# ==========================================
# 🔋 Swarm Battery & Thermal Monitor
# ==========================================
# Scans all ADB-connected mobile nodes and 
# reports health, temperature, and charging status.
# ==========================================

echo "🔍 Scanning Swarm for Battery Health..."
echo "--------------------------------------------------------------------------------"
printf "%-20s | %-12s | %-8s | %-12s | %-10s\n" "Device ID" "Role" "Level" "Temp" "Health"
echo "--------------------------------------------------------------------------------"

# Get list of devices (serial numbers)
DEVICES=$(adb devices | grep "device$" | awk '{print $1}')

if [ -z "$DEVICES" ]; then
    echo "❌ No devices found via ADB."
    exit 0
fi

for SERIAL in $DEVICES; do
    # Get model and battery info
    MODEL=$(adb -s "$SERIAL" shell getprop ro.product.model | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
    
    # Extract battery details
    BATT_INFO=$(adb -s "$SERIAL" shell dumpsys battery)
    LEVEL=$(echo "$BATT_INFO" | grep "level:" | awk '{print $2}' | tr -d '\r')
    TEMP_RAW=$(echo "$BATT_INFO" | grep "temperature:" | awk '{print $2}' | tr -d '\r')
    HEALTH_CODE=$(echo "$BATT_INFO" | grep "health:" | awk '{print $2}' | tr -d '\r')

    # Convert Temperature (Android reports in 10ths of a degree)
    TEMP_C=$(echo "$TEMP_RAW / 10" | bc)
    
    # Map Health Codes
    case $HEALTH_CODE in
        2) HEALTH="Good" ;;
        3) HEALTH="Overheat" ;;
        4) HEALTH="Dead" ;;
        5) HEALTH="OverVolt" ;;
        *) HEALTH="Unknown" ;;
    esac

    # Determine Role (Try to find a matching service in the cluster)
    ROLE=$(kubectl get svc -n agent-execution -l "device-id=$MODEL" -o jsonpath='{.items[*].metadata.labels.agent-role}' 2>/dev/null || echo "scout")

    # Colorize output based on temperature
    # (Using basic ANSI codes for simplicity)
    if [ "$TEMP_C" -gt 40 ]; then
        TEMP_DISPLAY="${TEMP_C}°C 🔥"
    elif [ "$TEMP_C" -gt 35 ]; then
        TEMP_DISPLAY="${TEMP_C}°C ⚠️"
    else
        TEMP_DISPLAY="${TEMP_C}°C ✅"
    fi

    printf "%-20s | %-12s | %-8s | %-12s | %-10s\n" "$MODEL" "$ROLE" "$LEVEL%" "$TEMP_DISPLAY" "$HEALTH"
done

echo "--------------------------------------------------------------------------------"
echo "💡 Tip: If temperature exceeds 40°C, consider reducing LLM load."
