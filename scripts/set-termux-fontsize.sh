#!/usr/bin/env bash
# Set Termux font size on one or more fleet devices.
#
# Usage:
#   set-termux-fontsize.sh <size> [device ...]
#   set-termux-fontsize.sh 56 s20 s20plus moto   # set specific devices
#   set-termux-fontsize.sh 56                    # set all devices
#
# Flow per device:
#   1. SSH in → write fontsize into Termux SharedPreferences
#   2. ADB force-stop Termux (kills SSH too — that's expected)
#   3. ADB start Termux
#   4. ADB run-as to restart sshd
#   5. SSH back in → restart display session

set -euo pipefail

FONTSIZE=${1:?Usage: $0 <fontsize> [device ...]}
shift
TARGETS=("$@")

# All fleet devices if none specified
ALL_DEVICES=(s10e s20 s8 s20plus ph-1 moto)
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=("${ALL_DEVICES[@]}")

declare -A ADB_ADDR=(
    [s10e]=10.0.0.10:5555
    [s20]=10.0.0.20:5555
    [s8]=10.0.0.8:5555
    [s20plus]=10.0.0.200:5555
    [ph-1]=10.0.0.40:5555
    [moto]=10.0.0.30:5555
)
PREFS=/data/data/com.termux/shared_prefs/com.termux_preferences.xml

for host in "${TARGETS[@]}"; do
    adb_addr="${ADB_ADDR[$host]:?Unknown device: $host}"
    echo "=== $host (fontsize → $FONTSIZE) ==="

    # 1. Write fontsize into SharedPreferences over SSH
    echo -n "  modifying prefs ... "
    timeout 12 ssh -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
        "$host" "
        python3 - <<'PYEOF'
import re
path = '$PREFS'
text = open(path).read()
tag  = '<string name=\"fontsize\">$FONTSIZE</string>'
if 'name=\"fontsize\"' in text:
    text = re.sub(r'<string name=\"fontsize\">[^<]*</string>', tag, text)
else:
    text = text.replace('</map>', '    ' + tag + '\n</map>')
open(path, 'w').write(text)
PYEOF
    " && echo "ok" || { echo "FAILED — skipping $host"; continue; }

    # 2. Force-stop Termux via ADB (kills SSH — expected)
    echo -n "  restarting Termux ... "
    adb -s "$adb_addr" shell am force-stop com.termux
    sleep 2
    adb -s "$adb_addr" shell am start -n com.termux/com.termux.app.TermuxActivity >/dev/null
    sleep 4

    # 3. Restart sshd inside Termux via ADB
    echo -n "  starting sshd ... "
    adb -s "$adb_addr" shell \
        "run-as com.termux /data/data/com.termux/files/usr/bin/sshd 2>/dev/null || true"
    sleep 3

    # 4. Restart display dashboard over SSH
    echo -n "  restarting dashboard ... "
    timeout 15 ssh -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
        "$host" "
        export PATH=/data/data/com.termux/files/usr/bin:\$PATH
        tmux kill-session -t display 2>/dev/null
        bash ~/start-display.sh &>/dev/null &
    " && echo "ok" || echo "FAILED (may need wake-fleet-displays.sh)"

    echo "  done."
done
