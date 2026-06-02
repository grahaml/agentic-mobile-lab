#!/usr/bin/env bash
# Device-side telemetry push agent (Spec 2).
#
# Collects a coherent snapshot of system metrics AND the device's own Ollama
# state (from localhost:11434) and POSTs the bundle to the Macbuntu receiver.
# Designed to run on cron every 30 seconds in Termux. Fire-and-forget: any
# failure exits 0 so cron doesn't retry-storm.
#
# The two placeholder lines below are patched by install.sh — leave the
# __COLLECTOR_URL__ and __DEVICE_NAME__ markers intact so sed can find them.

COLLECTOR="__COLLECTOR_URL__"   # patched by install.sh
DEVICE_NAME="__DEVICE_NAME__"   # patched by install.sh

# --- Battery (sysfs → su sysfs → dumpsys fallback) -------------------------
# Direct sysfs reads fail without root on many OEMs. Try plain read first,
# then su -c on rooted devices, then dumpsys as a last resort.
BATT_PCT="null"
BATT_TEMP="null"
BATT_STATUS="unknown"
BATT_BASE="/sys/class/power_supply/battery"
_read_sysfs() { IFS= read -r -t 2 val < "$1" 2>/dev/null && printf '%s' "$val"; }
_read_sysfs_root() { su -c "cat '$1'" 2>/dev/null; }
_v=$(_read_sysfs "$BATT_BASE/capacity") && [ -n "$_v" ] && BATT_PCT="$_v"
_v=$(_read_sysfs "$BATT_BASE/temp")     && [ -n "$_v" ] && BATT_TEMP=$(awk -v t="$_v" 'BEGIN {printf "%.1f", t/10}')
_v=$(_read_sysfs "$BATT_BASE/status")   && [ -n "$_v" ] && BATT_STATUS=$(printf '%s' "$_v" | tr '[:upper:]' '[:lower:]')

# su fallback for rooted devices where sysfs is root-only (e.g. Motorola MTK)
if [ "$BATT_PCT" = "null" ] && command -v su >/dev/null 2>&1; then
    _v=$(_read_sysfs_root "$BATT_BASE/capacity") && [ -n "$_v" ] && BATT_PCT="$_v"
    _v=$(_read_sysfs_root "$BATT_BASE/temp")     && [ -n "$_v" ] && BATT_TEMP=$(awk -v t="$_v" 'BEGIN {printf "%.1f", t/10}')
    _v=$(_read_sysfs_root "$BATT_BASE/status")   && [ -n "$_v" ] && BATT_STATUS=$(printf '%s' "$_v" | tr '[:upper:]' '[:lower:]')
fi

if [ "$BATT_PCT" = "null" ] && command -v dumpsys >/dev/null 2>&1; then
    _DUMP=$(dumpsys battery 2>/dev/null)
    _v=$(printf '%s' "$_DUMP" | awk '/level:/ {print $2; exit}')
    [ -n "$_v" ] && BATT_PCT="$_v"
    _v=$(printf '%s' "$_DUMP" | awk '/temperature:/ {print $2; exit}')
    [ -n "$_v" ] && BATT_TEMP=$(awk -v t="$_v" 'BEGIN {printf "%.1f", t/10}')
    _v=$(printf '%s' "$_DUMP" | awk '/status:/ {print $2; exit}')
    case "$_v" in
        2) BATT_STATUS="charging" ;;
        3) BATT_STATUS="discharging" ;;
        4) BATT_STATUS="not charging" ;;
        5) BATT_STATUS="full" ;;
    esac
fi

# --- Memory (/proc/meminfo, kB -> MB) --------------------------------------
MEM_TOTAL="null"
MEM_AVAIL="null"
if [ -r /proc/meminfo ]; then
    MEM_TOTAL_KB=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
    MEM_AVAIL_KB=$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
    [ -n "$MEM_TOTAL_KB" ] && MEM_TOTAL=$(( MEM_TOTAL_KB / 1024 ))
    [ -n "$MEM_AVAIL_KB" ] && MEM_AVAIL=$(( MEM_AVAIL_KB / 1024 ))
fi

# --- Swap (/proc/swaps → su fallback → free -m fallback) -------------------
# /proc/swaps is root-gated on many OEMs. Fall back to `free -m` which reports
# swap totals in MB without requiring elevated permissions.
SWAP_TOTAL=0
SWAP_USED=0
if [ -r /proc/swaps ]; then
    SWAP_LINE=$(awk 'NR==2 {print $3, $4; exit}' /proc/swaps 2>/dev/null)
    if [ -n "$SWAP_LINE" ]; then
        SWAP_TOTAL_KB=$(printf '%s' "$SWAP_LINE" | awk '{print $1}')
        SWAP_USED_KB=$(printf '%s' "$SWAP_LINE" | awk '{print $2}')
        [ -n "$SWAP_TOTAL_KB" ] && SWAP_TOTAL=$(( SWAP_TOTAL_KB / 1024 ))
        [ -n "$SWAP_USED_KB" ] && SWAP_USED=$(( SWAP_USED_KB / 1024 ))
    fi
elif command -v su >/dev/null 2>&1; then
    SWAP_LINE=$(su -c "awk 'NR==2 {print \$3, \$4; exit}' /proc/swaps" 2>/dev/null)
    if [ -n "$SWAP_LINE" ]; then
        SWAP_TOTAL_KB=$(printf '%s' "$SWAP_LINE" | awk '{print $1}')
        SWAP_USED_KB=$(printf '%s' "$SWAP_LINE" | awk '{print $2}')
        [ -n "$SWAP_TOTAL_KB" ] && SWAP_TOTAL=$(( SWAP_TOTAL_KB / 1024 ))
        [ -n "$SWAP_USED_KB" ] && SWAP_USED=$(( SWAP_USED_KB / 1024 ))
    fi
fi

if [ "$SWAP_TOTAL" = "0" ] && command -v free >/dev/null 2>&1; then
    SWAP_LINE=$(free -m 2>/dev/null | awk '/^Swap:/ {print $2, $3; exit}')
    if [ -n "$SWAP_LINE" ]; then
        _st=$(printf '%s' "$SWAP_LINE" | awk '{print $1}')
        _su=$(printf '%s' "$SWAP_LINE" | awk '{print $2}')
        [ -n "$_st" ] && SWAP_TOTAL="$_st"
        [ -n "$_su" ] && SWAP_USED="$_su"
    fi
fi

# --- CPU temperature (thermal zones → su fallback → battery temp) ----------
CPU_TEMP="null"
for zone in /sys/class/thermal/thermal_zone*/temp; do
    if [ -r "$zone" ]; then
        RAW=$(_read_sysfs "$zone")
        if [ -n "$RAW" ] && [ "$RAW" -gt 0 ] 2>/dev/null; then
            CPU_TEMP=$(awk -v t="$RAW" 'BEGIN {printf "%.1f", t/1000}')
            break
        fi
    fi
done

if [ "$CPU_TEMP" = "null" ]; then
    # Glob may fail on kernels that deny directory listing — try known paths directly
    for zone in /sys/class/thermal/thermal_zone0/temp \
                /sys/devices/virtual/thermal/thermal_zone0/temp; do
        RAW=$(_read_sysfs "$zone")
        if [ -n "$RAW" ] && [ "$RAW" -gt 0 ] 2>/dev/null; then
            CPU_TEMP=$(awk -v t="$RAW" 'BEGIN {printf "%.1f", t/1000}')
            break
        fi
    done
fi

# su fallback for rooted devices where thermal sysfs is root-only
if [ "$CPU_TEMP" = "null" ] && command -v su >/dev/null 2>&1; then
    for zone in /sys/class/thermal/thermal_zone0/temp \
                /sys/devices/virtual/thermal/thermal_zone0/temp; do
        RAW=$(_read_sysfs_root "$zone")
        if [ -n "$RAW" ] && [ "$RAW" -gt 0 ] 2>/dev/null; then
            CPU_TEMP=$(awk -v t="$RAW" 'BEGIN {printf "%.1f", t/1000}')
            break
        fi
    done
fi

if [ "$CPU_TEMP" = "null" ] && [ "$BATT_TEMP" != "null" ]; then
    CPU_TEMP="$BATT_TEMP"
fi

# --- Ollama state from localhost (free during inference) -------------------
# --argjson requires valid JSON, so fall back to the literal string "null"
# whenever Ollama is down or returns garbage. jq then emits a real JSON null.
OLLAMA_PS=$(curl -s --max-time 2 http://localhost:11434/api/ps | jq -c '.' 2>/dev/null || echo "null")
[ -z "$OLLAMA_PS" ] && OLLAMA_PS="null"
OLLAMA_TAGS=$(curl -s --max-time 2 http://localhost:11434/api/tags | jq -c '.' 2>/dev/null || echo "null")
[ -z "$OLLAMA_TAGS" ] && OLLAMA_TAGS="null"

# --- Build the JSON bundle with jq -----------------------------------------
PAYLOAD=$(jq -n \
  --arg device "$DEVICE_NAME" \
  --argjson battery_pct "${BATT_PCT:-null}" \
  --argjson battery_temp_c "${BATT_TEMP:-null}" \
  --arg battery_status "${BATT_STATUS:-unknown}" \
  --argjson mem_total_mb "${MEM_TOTAL:-null}" \
  --argjson mem_available_mb "${MEM_AVAIL:-null}" \
  --argjson swap_total_mb "${SWAP_TOTAL:-0}" \
  --argjson swap_used_mb "${SWAP_USED:-0}" \
  --argjson cpu_temp_c "${CPU_TEMP:-null}" \
  --argjson ollama_ps "$OLLAMA_PS" \
  --argjson ollama_tags "$OLLAMA_TAGS" \
  '{device: $device,
    battery_pct: $battery_pct,
    battery_temp_c: $battery_temp_c,
    battery_status: $battery_status,
    mem_total_mb: $mem_total_mb,
    mem_available_mb: $mem_available_mb,
    swap_total_mb: $swap_total_mb,
    swap_used_mb: $swap_used_mb,
    cpu_temp_c: $cpu_temp_c,
    ollama_ps: $ollama_ps,
    ollama_tags: $ollama_tags}')

# --- POST. Always exit 0 — cron handles cadence. ---------------------------
curl -s --max-time 5 -X POST "$COLLECTOR" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" >/dev/null 2>&1

exit 0
