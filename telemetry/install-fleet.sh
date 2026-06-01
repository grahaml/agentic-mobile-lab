#!/usr/bin/env bash
# Install the telemetry push agent on every device in the fleet.
#
# Reads device list from telemetry/fleet.yaml. For each device,
# scp's the agent files over SSH and runs install.sh remotely. SSH config
# alias (Host name matching the device name) is preferred; falls back to
# the raw IP for devices without a config entry.
#
# Usage:
#   bash telemetry/install-fleet.sh                  # autodetect collector IP
#   bash telemetry/install-fleet.sh --collector-ip 10.0.0.5
#   bash telemetry/install-fleet.sh --only s10e,ph1  # subset
#
# Skips any device that fails to connect — does not abort the whole run.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$SCRIPT_DIR/agent"
SSH_PORT=8022

COLLECTOR_IP=""
ONLY_FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --collector-ip) COLLECTOR_IP="$2"; shift 2;;
        --only) ONLY_FILTER="$2"; shift 2;;
        -h|--help)
            sed -n '2,15p' "$0"; exit 0;;
        *) echo "unknown arg: $1" >&2; exit 1;;
    esac
done

# --- Collector IP: prefer arg, else use this machine's static lab IP -------
if [ -z "$COLLECTOR_IP" ]; then
    COLLECTOR_IP="10.0.0.11"
fi

# --- Parse devices from fleet.yaml -----------------------------------------
CONFIG="$SCRIPT_DIR/fleet.yaml"
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: $CONFIG not found" >&2
    exit 1
fi

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

if [ -z "$DEVICES" ]; then
    echo "ERROR: no devices found in $CONFIG" >&2
    exit 1
fi

# --- Subset filter ---------------------------------------------------------
if [ -n "$ONLY_FILTER" ]; then
    FILTER_RE=$(echo "$ONLY_FILTER" | sed 's/,/|/g')
    DEVICES=$(echo "$DEVICES" | awk -v re="^($FILTER_RE)\t" '$0 ~ re')
fi

# --- Verify agent files exist ----------------------------------------------
for f in metrics_push.sh install.sh; do
    if [ ! -f "$AGENT_DIR/$f" ]; then
        echo "ERROR: $AGENT_DIR/$f not found" >&2
        exit 1
    fi
done

# --- Roll out --------------------------------------------------------------
echo "Collector: http://$COLLECTOR_IP:8765/metrics"
echo ""

OK_COUNT=0
FAIL_COUNT=0
FAIL_NAMES=""

while IFS=$'\t' read -r NAME IP; do
    [ -z "$NAME" ] && continue

    # Find an SSH config alias whose HostName equals this device's IP.
    # That way we pick up the right IdentityFile, User, and Port without
    # having to guess at name conventions (fleet.yaml uses "ph1",
    # ssh config uses "ph-1"; telemetry has "s20fe", ssh has "s20"; etc.)
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

    # Stage the agent files on the device.
    # -n on every ssh call is critical: without it, ssh reads from the while
    # loop's stdin and consumes remaining device lines, processing only the first.
    REMOTE_DIR="~/telemetry-agent"
    # shellcheck disable=SC2086
    ssh -n $SSH_OPTS -o ConnectTimeout=5 -o BatchMode=yes "$SSH_TARGET" \
        "mkdir -p $REMOTE_DIR" 2>/dev/null
    if [ "$?" -ne 0 ]; then
        echo "    SSH connect failed — skipping"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_NAMES="$FAIL_NAMES $NAME"
        echo ""
        continue
    fi

    # Transfer via ssh pipe (not scp) to avoid key issues.
    # No -n here: < "$AGENT_FILE" provides stdin, so the while loop's stdin
    # is not consumed. -n is only needed on commands without a stdin redirect.
    for AGENT_FILE in "$AGENT_DIR/metrics_push.sh" "$AGENT_DIR/install.sh"; do
        FNAME=$(basename "$AGENT_FILE")
        # shellcheck disable=SC2086
        ssh $SSH_OPTS -o ConnectTimeout=5 "$SSH_TARGET" \
            "cat > $REMOTE_DIR/$FNAME && chmod +x $REMOTE_DIR/$FNAME" \
            < "$AGENT_FILE" 2>&1 | sed 's/^/    /'
        if [ "${PIPESTATUS[0]:-1}" -ne 0 ]; then
            echo "    transfer failed ($FNAME) — skipping"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            FAIL_NAMES="$FAIL_NAMES $NAME"
            echo ""
            continue 2
        fi
    done

    # Run install.sh on the device
    # shellcheck disable=SC2086
    ssh -n $SSH_OPTS -o ConnectTimeout=5 "$SSH_TARGET" \
        "cd $REMOTE_DIR && bash install.sh $COLLECTOR_IP $NAME" \
        2>&1 | sed 's/^/    /'
    RC=${PIPESTATUS[0]:-1}
    if [ "$RC" -eq 0 ]; then
        OK_COUNT=$((OK_COUNT + 1))
    else
        echo "    install.sh exit $RC"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_NAMES="$FAIL_NAMES $NAME"
    fi
    echo ""
done <<< "$DEVICES"

echo "==================================="
echo "Installed: $OK_COUNT  Failed: $FAIL_COUNT"
[ -n "$FAIL_NAMES" ] && echo "Failed devices:$FAIL_NAMES"
