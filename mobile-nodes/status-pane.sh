#!/data/data/com.termux/files/usr/bin/bash
# Right-pane status display for the fleet rack display.
# Reads metrics from ~/.last_metrics.json written by metrics_push.sh (every 30s).
# Falls back to direct reads on first boot before cron has fired.

export PATH="/data/data/com.termux/files/usr/bin:$PATH"

CONFIG="$HOME/.device-info"
CACHE="$HOME/.last_metrics.json"

print_status() {
    local name role ip model ssh_st ollama_st bat temp uptime_str

    name=$(grep "^name=" "$CONFIG" 2>/dev/null | cut -d= -f2)
    role=$(grep "^role=" "$CONFIG" 2>/dev/null | cut -d= -f2)
    [ -z "$name" ] && name="unknown"
    [ -z "$role" ] && role="unknown"

    ip=$(ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    [ -z "$ip" ] && ip="no wifi"

    if [ -f "$CACHE" ] && command -v jq >/dev/null 2>&1; then
        bat=$(jq -r 'if .battery_pct != null then (.battery_pct|tostring)+"%" else "?" end' "$CACHE" 2>/dev/null)
        temp=$(jq -r 'if .cpu_temp_c != null then (.cpu_temp_c|tostring)+"°C" else "?" end' "$CACHE" 2>/dev/null)
        model=$(jq -r '(.ollama_tags.models[0].name? // "none") | split(":")[0]' "$CACHE" 2>/dev/null)
        ollama_st=$(jq -r 'if .ollama_tags != null then "UP" else "DOWN" end' "$CACHE" 2>/dev/null)
    else
        # Cache not ready yet (first boot) — direct reads
        local raw
        raw=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null \
            || cat /sys/class/power_supply/Battery/capacity 2>/dev/null || echo "")
        [ -n "$raw" ] && bat="${raw}%" || bat="?"
        temp=$(awk '{printf "%.0f°C", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "?")
        model=$(grep "^model=" "$CONFIG" 2>/dev/null | cut -d= -f2 || echo "?")
        curl -s --connect-timeout 2 http://localhost:11434/api/tags >/dev/null 2>&1 \
            && ollama_st="UP" || ollama_st="DOWN"
    fi

    pgrep sshd >/dev/null 2>&1 && ssh_st="UP" || ssh_st="DOWN"
    uptime_str=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')

    clear
    printf "\n"
    printf " %s\n" "$name"
    printf " %s\n" "$role"
    printf " ─────────────\n"
    printf " %s\n" "$ip"
    printf "\n"
    printf " model\n"
    printf "  %s\n" "$model"
    printf "\n"
    printf " ssh    %s\n" "$ssh_st"
    printf " ollama %s\n" "$ollama_st"
    printf "\n"
    printf " bat  %s\n" "$bat"
    printf " temp %s\n" "$temp"
    printf "\n"
    printf " up: %s\n" "$uptime_str"
}

while true; do
    print_status
    sleep 10
done
