#!/bin/bash

# ==========================================
# 🚀 LineageOS Mobile Node Provisioner (PH-1 Optimized)
# ==========================================
# This version handles the PH-1 (Mata) specifics and 
# fixes the Ubuntu Chroot "Environment Leak".
# ==========================================

set -e

# Configuration
ADB_BIN="${ADB_BIN:-$(which adb)}"
UBUNTU_ROOT="/data/local/ubuntu"
TERMUX_HOME="/data/data/com.termux/files/home"
MODEL_NAME="qwen2.5-coder:1.5b"
AID_INET=3003
AID_NET_RAW=3004

# --- Root & Identity Bridge Logic ---

# 1. Detect Root Method (ADB)
if $ADB_BIN shell id | grep -q "uid=0"; then
    ADB_ROOT_PREFIX=""
    echo "✅ ADB is already running as root."
else
    ADB_ROOT_PREFIX="su -c "
    echo "✅ Root access via 'su' (Standard ADB)."
fi

run_adb_root() {
    local cmd="$1"
    if [ -z "$ADB_ROOT_PREFIX" ]; then
        $ADB_BIN shell "$cmd"
    else
        $ADB_BIN shell "su -c '$cmd'"
    fi
}

# 2. Get Device Metadata
SERVICE_ROLE=${1:-"scout"}
PHONE_IP=${2:-"192.168.4.58"}
DEVICE_MODEL=$($ADB_BIN -s "$PHONE_IP" shell getprop ro.product.model | tr -d '\r' | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')
PERSONA_NAME="${SERVICE_ROLE}-${DEVICE_MODEL}"
DEVICE_KEY="$HOME/.ssh/id_mobile_$PERSONA_NAME"

echo "🛰️  Provisioning: $PERSONA_NAME ($PHONE_IP)"

# 3. Setup SSH Key (Host-to-Phone)
if [ ! -f "$DEVICE_KEY" ]; then
    echo "🔑 Generating key: $DEVICE_KEY"
    ssh-keygen -t ed25519 -f "$DEVICE_KEY" -N "" -C "agent-lab@$PERSONA_NAME"
fi

# 4. Identify Termux User
TERMUX_UID=$($ADB_BIN -s "$PHONE_IP" shell "dumpsys package com.termux | grep appId=" | head -n 1 | sed 's/.*Id=\([0-9]*\).*/\1/' | tr -d '\r')
if [ -z "$TERMUX_UID" ]; then TERMUX_UID="10191"; fi # Fallback
TERMUX_USER="u0_a$((TERMUX_UID - 10000))"

# 5. Authorize SSH Key (via ADB Root)
echo "🔑 Authorizing SSH key..."
run_adb_root "mkdir -p $TERMUX_HOME/.ssh"
$ADB_BIN -s "$PHONE_IP" push "${DEVICE_KEY}.pub" /data/local/tmp/mobile_key.pub
run_adb_root "cat /data/local/tmp/mobile_key.pub >> $TERMUX_HOME/.ssh/authorized_keys && \
             chown -R $TERMUX_UID:$TERMUX_UID $TERMUX_HOME/.ssh && \
             chmod 700 $TERMUX_HOME/.ssh && \
             chmod 600 $TERMUX_HOME/.ssh/authorized_keys && \
             rm /data/local/tmp/mobile_key.pub"

# 6. Helper for SSH commands
run_ssh() {
    ssh -i "$DEVICE_KEY" -p 8022 -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$TERMUX_USER@$PHONE_IP" "export PATH=/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:\$PATH && $1"
}

# --- 7. Ubuntu Identity Bridge (GID Alignment) ---
echo "🛠️  Checking Ubuntu Chroot at $UBUNTU_ROOT..."
if ! run_adb_root "ls -d $UBUNTU_ROOT >/dev/null 2>&1"; then
    echo "❌ ERROR: Ubuntu root not found at $UBUNTU_ROOT. Please install it first."
    exit 1
fi

echo "🛠️  Aligning Ubuntu GIDs with Android networking..."
run_adb_root "grep -q 'aid_inet' $UBUNTU_ROOT/etc/group || echo 'aid_inet:x:$AID_INET:' >> $UBUNTU_ROOT/etc/group"
run_adb_root "grep -q 'aid_net_raw' $UBUNTU_ROOT/etc/group || echo 'aid_net_raw:x:$AID_NET_RAW:' >> $UBUNTU_ROOT/etc/group"
run_adb_root "grep -q 'agent-lab' $UBUNTU_ROOT/etc/passwd || echo 'agent-lab:x:1000:1000:Agent Lab:/home/agent-lab:/bin/bash' >> $UBUNTU_ROOT/etc/passwd"
run_adb_root "grep -q 'agent-lab' $UBUNTU_ROOT/etc/group || echo 'agent-lab:x:1000:' >> $UBUNTU_ROOT/etc/group"
run_adb_root "mkdir -p $UBUNTU_ROOT/home/agent-lab && chown -R 1000:1000 $UBUNTU_ROOT/home/agent-lab"
run_adb_root "sed -i 's/aid_inet:x:3003:/aid_inet:x:3003:agent-lab/' $UBUNTU_ROOT/etc/group"
run_adb_root "sed -i 's/aid_net_raw:x:3004:/aid_net_raw:x:3004:agent-lab/' $UBUNTU_ROOT/etc/group"

# --- 8. Execution Phase ---

echo "👻 Hardening background stability..."
$ADB_BIN -s "$PHONE_IP" shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647" >/dev/null 2>&1 || true
$ADB_BIN -s "$PHONE_IP" shell settings put global wifi_sleep_policy 2 >/dev/null 2>&1 || true
$ADB_BIN -s "$PHONE_IP" shell dumpsys deviceidle whitelist +com.termux >/dev/null 2>&1 || true

echo "📦 Configuring Termux environment..."
run_ssh "pkg update && pkg install openssh -y >/dev/null 2>&1"
run_ssh "termux-wake-lock || true"

# --- 8b. Services & Persistence ---
echo "🔧 Configuring services & Termux:Boot persistence..."

# Generate services script (starts sshd + mounts chroot + starts ollama, no dashboard)
SERVICES_SCRIPT=$(cat << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

pgrep sshd >/dev/null || sshd

su -c '
    UBUNTU_ROOT="/data/local/ubuntu"
    mount | grep -q "$UBUNTU_ROOT/proc" || mount -t proc proc "$UBUNTU_ROOT/proc"
    mount | grep -q "$UBUNTU_ROOT/sys" || mount -t sysfs sys "$UBUNTU_ROOT/sys"
    mount | grep -q "$UBUNTU_ROOT/dev" || mount --bind /dev "$UBUNTU_ROOT/dev"
    mount | grep -q "$UBUNTU_ROOT/dev/pts" || mount --bind /dev/pts "$UBUNTU_ROOT/dev/pts"
    su -g 3003 -c "chroot /data/local/ubuntu /usr/bin/setpriv --reuid=1000 --regid=1000 --groups=1000,3003 /usr/bin/env -i HOME=/home/agent-lab TERM=xterm PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TMPDIR=/tmp /bin/bash -c \"pgrep ollama >/dev/null || (export OLLAMA_HOST=0.0.0.0 && /usr/local/bin/ollama serve > /home/agent-lab/ollama.log 2>&1 &)\""
'
EOF
)

# Push services script via SSH
run_ssh "cat > ~/start-services.sh << 'SERVICES_EOF'
$SERVICES_SCRIPT
SERVICES_EOF
chmod +x ~/start-services.sh"

# Configure Termux:Boot
run_ssh "mkdir -p ~/.termux/boot && echo -e '#!/data/data/com.termux/files/usr/bin/bash\ntermux-wake-lock\nsshd\n~/start-services.sh' > ~/.termux/boot/start-agent && chmod +x ~/.termux/boot/start-agent"

echo "📁 Mounting filesystems and fixing /tmp for chroot..."
run_adb_root "mount -t proc proc $UBUNTU_ROOT/proc || true"
run_adb_root "mount -t sysfs sys $UBUNTU_ROOT/sys || true"
run_adb_root "mount --bind /dev $UBUNTU_ROOT/dev || true"
run_adb_root "mount --bind /dev/pts $UBUNTU_ROOT/dev/pts || true"
run_adb_root "echo 'nameserver 8.8.8.8' > $UBUNTU_ROOT/etc/resolv.conf"

# CRITICAL: Fix for ca-certificates / mktemp error
run_adb_root "mkdir -p $UBUNTU_ROOT/tmp && chmod 1777 $UBUNTU_ROOT/tmp"

echo "🧪 Configuring Apt (No-Sandbox) and dependencies..."
run_adb_root "echo 'APT::Sandbox::User \"root\";' > $UBUNTU_ROOT/etc/apt/apt.conf.d/99-no-sandbox"

# Use a highly isolated environment string for chroot
CHROOT_ENV="/usr/bin/env -i HOME=/root TERM=$TERM PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TMPDIR=/tmp"
CHROOT_EXEC="chroot $UBUNTU_ROOT $CHROOT_ENV /bin/bash -c"

echo "🛠️  Repairing broken packages and installing dependencies..."
run_adb_root "$CHROOT_EXEC 'apt update && apt install -y -f && apt install -y python3-venv python3-pip curl ca-certificates zstd'"

# 9. Ollama Installation (Idempotent)
if run_adb_root "$CHROOT_EXEC 'ls /usr/local/bin/ollama >/dev/null 2>&1'"; then
    echo "✅ Ollama binary already exists."
else
    echo "📥 Installing Ollama..."
    run_adb_root "$CHROOT_EXEC 'curl -fsSL https://ollama.com/install.sh | sh'"
fi

# 10. User Environment Setup (venv & models)
echo "🐍 Setting up Python venv as agent-lab..."
# su fails in chroot, and toybox chroot doesn't support --userspec.
# setpriv is the most reliable way to drop privileges in this Ubuntu Noble chroot.
# CRITICAL: We MUST include group 3003 (aid_inet) for Android network access.
CHROOT_USER="chroot $UBUNTU_ROOT /usr/bin/setpriv --reuid=1000 --regid=1000 --groups=1000,3003 /usr/bin/env -i HOME=/home/agent-lab TERM=$TERM PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin TMPDIR=/tmp /bin/bash -c"

run_adb_root "$CHROOT_USER 'python3 -m venv ~/venv && ~/venv/bin/pip install --upgrade pip llm llm-ollama'"

echo "📥 Bootstrapping $MODEL_NAME..."
# Start ollama as agent-lab (OLLAMA_HOST=0.0.0.0 for cluster access)
run_adb_root "$CHROOT_USER 'pgrep ollama >/dev/null || (export OLLAMA_HOST=0.0.0.0 && /usr/local/bin/ollama serve > ~/ollama.log 2>&1 & sleep 5)'"
run_adb_root "$CHROOT_USER 'export OLLAMA_HOST=0.0.0.0 && /usr/local/bin/ollama pull $MODEL_NAME'"

# 11. Cluster Bridge
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"$DIR/bridge-phone.sh" "$PHONE_IP" "$SERVICE_ROLE" "$DEVICE_MODEL"

# 12. Telemetry Agent (inside Ubuntu chroot)
# Install jq + cron, copy the push script, and wire up a crontab entry.
echo "📡 Installing telemetry push agent in Ubuntu chroot..."
HERMES_REPO="$(cd "$DIR/../../hermes-experimentation" 2>/dev/null && pwd || true)"
METRICS_SCRIPT="$HERMES_REPO/telemetry/agent/metrics_push.sh"
if [ -z "$HERMES_REPO" ] || [ ! -f "$METRICS_SCRIPT" ]; then
    echo "⚠️  hermes-experimentation repo not found — skipping telemetry install."
    echo "    Set HERMES_REPO=/path/to/hermes-experimentation and re-run step 12 manually."
else
    COLLECTOR_IP="${COLLECTOR_IP:-10.0.0.11}"
    COLLECTOR_URL="http://${COLLECTOR_IP}:8765/metrics"
    AGENT_DIR="/home/agent-lab/telemetry-agent"

    # Install deps in chroot
    run_adb_root "$CHROOT_EXEC 'apt install -y jq cron'"

    # Copy and patch the push script
    run_adb_root "mkdir -p $UBUNTU_ROOT$AGENT_DIR"
    $ADB_BIN push "$METRICS_SCRIPT" "/data/local/tmp/metrics_push.sh"
    run_adb_root "cp /data/local/tmp/metrics_push.sh $UBUNTU_ROOT$AGENT_DIR/metrics_push.sh"
    run_adb_root "sed -i 's|__COLLECTOR_URL__|${COLLECTOR_URL}|g; s|__DEVICE_NAME__|${SERVICE_ROLE}|g' $UBUNTU_ROOT$AGENT_DIR/metrics_push.sh"
    run_adb_root "chmod +x $UBUNTU_ROOT$AGENT_DIR/metrics_push.sh && chown -R 1000:1000 $UBUNTU_ROOT$AGENT_DIR"

    # Wire crontab inside chroot
    CRON_LINE="* * * * * $AGENT_DIR/metrics_push.sh"
    CRON_LINE2="* * * * * sleep 30 && $AGENT_DIR/metrics_push.sh"
    run_adb_root "$CHROOT_USER '(crontab -l 2>/dev/null | grep -qF metrics_push) || (crontab -l 2>/dev/null; echo \"$CRON_LINE\"; echo \"$CRON_LINE2\") | crontab -'"
    run_adb_root "$CHROOT_EXEC 'service cron start 2>/dev/null || cron 2>/dev/null || true'"

    # Fire one immediate push
    run_adb_root "$CHROOT_USER '$AGENT_DIR/metrics_push.sh'"
    echo "📡 Telemetry agent installed in chroot (pushing to $COLLECTOR_URL as '$SERVICE_ROLE')."
fi

echo "✅ Provisioning Complete for $PERSONA_NAME!"
echo "📶 Access via: ssh -i $DEVICE_KEY -p 8022 $TERMUX_USER@$PHONE_IP"
