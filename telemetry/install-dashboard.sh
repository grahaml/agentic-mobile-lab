#!/usr/bin/env bash
# Deploy the device-side Rich dashboard to all fleet nodes.
#
# Copies dashboard.py, device_dashboard.py, and models.py to ~/telemetry/,
# copies start-display.sh to ~/start-display.sh, wires Termux:Boot auto-start,
# and adds a `display` alias to ~/.bashrc for manual invocation.
#
# Usage:
#   bash telemetry/install-dashboard.sh                # all devices
#   bash telemetry/install-dashboard.sh --only s10e,ph1
#
# Skips any device that fails to connect — does not abort the whole run.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SSH_PORT=8022
ONLY_FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY_FILTER="$2"; shift 2 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

CONFIG="$SCRIPT_DIR/fleet.yaml"
[ -f "$CONFIG" ] || { echo "ERROR: $CONFIG not found" >&2; exit 1; }

DASHBOARD_PY="$SCRIPT_DIR/dashboard.py"
DEVICE_DASHBOARD_PY="$SCRIPT_DIR/device_dashboard.py"
MODELS_PY="$SCRIPT_DIR/models.py"
START_DISPLAY_SH="$REPO_ROOT/mobile-nodes/start-display.sh"

for f in "$DASHBOARD_PY" "$DEVICE_DASHBOARD_PY" "$MODELS_PY" "$START_DISPLAY_SH"; do
    [ -f "$f" ] || { echo "ERROR: $f not found" >&2; exit 1; }
done

DEVICES=$(python3 -c "
import yaml, sys
with open('$CONFIG') as f:
    cfg = yaml.safe_load(f) or {}
seen = set()
for tier_body in (cfg.get('tiers') or {}).values():
    for d in (tier_body or {}).get('devices', []) or []:
        name = d.get('name')
        if not name or name in seen:
            continue
        seen.add(name)
        url = d.get('base_url', '')
        host = url.split('//', 1)[-1].split(':', 1)[0]
        print(f'{name}\t{host}')
")

[ -z "$DEVICES" ] && { echo "ERROR: no devices found in $CONFIG" >&2; exit 1; }

if [ -n "$ONLY_FILTER" ]; then
    FILTER_RE=$(echo "$ONLY_FILTER" | sed 's/,/|/g')
    DEVICES=$(echo "$DEVICES" | awk -v re="^($FILTER_RE)\t" '$0 ~ re')
fi

OK_COUNT=0
FAIL_COUNT=0
FAIL_NAMES=""

while IFS=$'\t' read -r NAME IP; do
    [ -z "$NAME" ] && continue

    SSH_ALIAS=$(awk -v ip="$IP" '
        /^[Hh]ost / { host = $2 }
        /^[ \t]*[Hh]ost[Nn]ame / && $2 == ip { print host; exit }
    ' ~/.ssh/config 2>/dev/null)

    if [ -n "$SSH_ALIAS" ]; then
        SSH_TARGET="$SSH_ALIAS"
        SSH_OPTS=""
    else
        SSH_TARGET="$IP"
        SSH_OPTS="-p $SSH_PORT -o StrictHostKeyChecking=no"
    fi

    echo ">>> $NAME ($IP via $SSH_TARGET)"

    # One handshake, all operations reuse it — avoids per-transfer timeout on
    # slow SSH servers (e.g. rooted devices with Ubuntu chroot).
    CTRL_SOCK="/tmp/ssh_ctl_${NAME}_$$"
    # shellcheck disable=SC2086
    if ! ssh -n $SSH_OPTS \
            -o ConnectTimeout=15 -o BatchMode=yes \
            -o ControlMaster=yes -o ControlPath="$CTRL_SOCK" -o ControlPersist=120 \
            "$SSH_TARGET" "mkdir -p ~/telemetry" 2>/dev/null; then
        echo "    SSH connect failed — skipping"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_NAMES="$FAIL_NAMES $NAME"
        echo ""
        continue
    fi
    REUSE="-o ControlPath=$CTRL_SOCK -o ControlMaster=no"

    # Transfer source files (stdin redirect provides file content; no -n)
    FAILED=0
    for PAIR in \
        "$DASHBOARD_PY|~/telemetry/dashboard.py" \
        "$DEVICE_DASHBOARD_PY|~/telemetry/device_dashboard.py" \
        "$MODELS_PY|~/telemetry/models.py" \
        "$START_DISPLAY_SH|~/start-display.sh" \
    ; do
        SRC="${PAIR%%|*}"
        DST="${PAIR##*|}"
        # shellcheck disable=SC2086
        ssh $SSH_OPTS $REUSE "$SSH_TARGET" "cat > $DST" < "$SRC" 2>&1 | sed 's/^/    /'
        if [ "${PIPESTATUS[0]:-1}" -ne 0 ]; then
            echo "    transfer failed ($(basename "$SRC")) — skipping"
            FAILED=1
            break
        fi
        echo "    -> $DST"
    done

    if [ "$FAILED" -eq 1 ]; then
        ssh -O exit -o ControlPath="$CTRL_SOCK" "$SSH_TARGET" 2>/dev/null || true
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_NAMES="$FAIL_NAMES $NAME"
        echo ""
        continue
    fi

    # Remote setup: rich, __init__.py, Termux:Boot entry, .bashrc alias.
    # Heredoc provides stdin — no -n flag here.
    # shellcheck disable=SC2086
    ssh $SSH_OPTS $REUSE "$SSH_TARGET" bash << 'REMOTE' 2>&1 | sed 's/^/    /'
set -e

# Pin a known-good Termux mirror before any pkg calls to avoid the
# auto-selector picking a bad one on first boot
echo "deb https://packages-cf.termux.dev/apt/termux-main stable main" \
    > /data/data/com.termux/files/usr/etc/apt/sources.list
apt-get update -q || true

# Ensure python3 is available in the Termux session (rooted devices have it
# only in the Ubuntu chroot — install the Termux-native package instead)
python3 -c "" 2>/dev/null || pkg install -y python

python3 -c "import rich" 2>/dev/null || python3 -m pip install rich --quiet

# Namespace package marker so 'from telemetry.X import Y' resolves correctly
touch ~/telemetry/__init__.py

chmod +x ~/start-display.sh

# Termux:Boot: launch the display session on every reboot
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-display << 'BOOT_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
bash ~/start-display.sh
BOOT_SCRIPT
chmod +x ~/.termux/boot/start-display

# .bashrc alias for manual invocation when auto-start fails
grep -qF "alias display=" ~/.bashrc 2>/dev/null \
    || echo "alias display='bash ~/start-display.sh'" >> ~/.bashrc

echo "setup complete"
REMOTE
    RC=${PIPESTATUS[0]:-1}
    ssh -O exit -o ControlPath="$CTRL_SOCK" "$SSH_TARGET" 2>/dev/null || true
    if [ "$RC" -eq 0 ]; then
        OK_COUNT=$((OK_COUNT + 1))
    else
        echo "    remote setup exit $RC"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_NAMES="$FAIL_NAMES $NAME"
    fi
    echo ""
done <<< "$DEVICES"

echo "==================================="
echo "Installed: $OK_COUNT  Failed: $FAIL_COUNT"
[ -n "$FAIL_NAMES" ] && echo "Failed devices:$FAIL_NAMES"
