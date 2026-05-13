#!/bin/bash

# ==========================================
# 🔋 Swarm Battery & Thermal Monitor v2.0
# ==========================================
# Hybrid monitoring: Uses ADB (USB) or SSH (Network)
# to report health and temperature for all nodes.
# ==========================================

echo "🔍 Scanning Swarm for Battery Health..."
echo "--------------------------------------------------------------------------------"
printf "%-25s | %-8s | %-8s | %-12s | %-10s\n" "Device ID" "Source" "Level" "Temp" "Health"
echo "--------------------------------------------------------------------------------"

# --- 1. Get Cluster Service List ---
# This gives us the target names and expected IPs
SVC_LIST=$(kubectl get svc -n agent-execution -l device-type=mobile -o jsonpath='{range .items[*]}{.metadata.name}{","}{.spec.clusterIP}{","}{.metadata.labels.device-id}{"\n"}{end}')

# --- 2. Get ADB Serial List ---
ADB_DEVICES=$(adb devices | grep "device$" | awk '{print $1}')

# Process each service in the cluster
while IFS=',' read -r SVC_NAME CLUSTER_IP DEVICE_ID; do
    [ -z "$SVC_NAME" ] && continue
    
    SOURCE="SSH"
    DATA_FOUND=false
    
    # Try ADB First if the device-id matches an ADB serial (simple heuristic)
    for SERIAL in $ADB_DEVICES; do
        ADB_MODEL=$(adb -s "$SERIAL" shell getprop ro.product.model | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
        if [ "$ADB_MODEL" = "$DEVICE_ID" ] || [ "$SERIAL" = "$DEVICE_ID" ]; then
            BATT_INFO=$(adb -s "$SERIAL" shell dumpsys battery)
            LEVEL=$(echo "$BATT_INFO" | grep "level:" | awk '{print $2}' | tr -d '\r')
            TEMP_RAW=$(echo "$BATT_INFO" | grep "temperature:" | awk '{print $2}' | tr -d '\r')
            HEALTH_CODE=$(echo "$BATT_INFO" | grep "health:" | awk '{print $2}' | tr -d '\r')
            TEMP_C=$(echo "$TEMP_RAW / 10" | bc)
            
            case $HEALTH_CODE in
                2) HEALTH="Good" ;;
                3) HEALTH="Overheat" ;;
                4) HEALTH="Dead" ;;
                *) HEALTH="Unknown" ;;
            esac
            
            SOURCE="ADB"
            DATA_FOUND=true
            break
        fi
    done
    
    # If not found via ADB, try SSH to the Endpoint IP
    if [ "$DATA_FOUND" = false ]; then
        # Get the actual Endpoint IP (not cluster IP)
        ENDPOINT_IP=$(kubectl get ep "$SVC_NAME" -n agent-execution -o jsonpath='{.subsets[0].addresses[0].ip}')
        KEY="$HOME/.ssh/id_mobile_$SVC_NAME"
        
        if [ -n "$ENDPOINT_IP" ] && [ -f "$KEY" ]; then
            # Attempt SSH poll - using -n to prevent consuming stdin
            BATT_DATA=$(ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$KEY" -p 8022 "$ENDPOINT_IP" "cat /sys/class/power_supply/battery/capacity /sys/class/power_supply/battery/temp /sys/class/power_supply/battery/health" 2>/dev/null || true)
            
            if [ -n "$BATT_DATA" ]; then
                LEVEL=$(echo "$BATT_DATA" | sed -n '1p')
                TEMP_RAW=$(echo "$BATT_DATA" | sed -n '2p')
                HEALTH_RAW=$(echo "$BATT_DATA" | sed -n '3p' | tr '[:upper:]' '[:lower:]')
                
                # Handle cases where some files might be missing
                [ -z "$LEVEL" ] && LEVEL="?"
                [ -z "$TEMP_RAW" ] && TEMP_RAW="0"
                [ -z "$HEALTH_RAW" ] && HEALTH_RAW="unknown"

                # Temp can be in 10ths (350) or degrees (35) depending on kernel
                if [ "$TEMP_RAW" -gt 200 ]; then
                    TEMP_C=$(echo "$TEMP_RAW / 10" | bc)
                else
                    TEMP_C=$TEMP_RAW
                fi
                
                HEALTH=$(echo "$HEALTH_RAW" | sed 's/./\u&/')
                DATA_FOUND=true
            fi
        fi
    fi
    
    # Display Result
    if [ "$DATA_FOUND" = true ]; then
        # Colorize
        if [ "$TEMP_C" -gt 40 ]; then
            TEMP_DISPLAY="${TEMP_C}°C 🔥"
        elif [ "$TEMP_C" -gt 35 ]; then
            TEMP_DISPLAY="${TEMP_C}°C ⚠️"
        else
            TEMP_DISPLAY="${TEMP_C}°C ✅"
        fi
        
        printf "%-25s | %-8s | %-8s | %-12s | %-10s\n" "$SVC_NAME" "$SOURCE" "$LEVEL%" "$TEMP_DISPLAY" "$HEALTH"
    else
        printf "%-25s | %-8s | %-8s | %-12s | %-10s\n" "$SVC_NAME" "OFFLINE" "-" "-" "-"
    fi

done <<EOF
$SVC_LIST
EOF

echo "--------------------------------------------------------------------------------"
echo "💡 Tip: If temperature exceeds 40°C, consider reducing LLM load."
