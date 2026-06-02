#!/bin/bash

# ==========================================
# 🚀 Automated Mobile Node Provisioner
# ==========================================
# Run this from Macbuntu to setup a connected/rooted phone.
# ==========================================

set -e

# Configuration
UBUNTU_ROOT="/data/local/ubuntu"
TERMUX_HOME="/data/data/com.termux/files/home"
MODEL_NAME="qwen2.5-coder:1.5b"

# 1. Identity Siphoning (Hardware vs. Role)
if ! adb devices | grep -q "device$"; then
    echo "❌ ERROR: No device found via ADB (or it's in sideload/recovery mode)."
    exit 1
fi

# 1b. Prerequisites Check (Manual Installation Required)
TERMUX_PACKAGE="com.termux"
TERMUX_BOOT_PACKAGE="com.termux.boot"

# Use filesystem check to avoid Binder errors on pm list (requires su for /data/data)
if ! adb shell "su -c 'ls -d /data/data/$TERMUX_PACKAGE' >/dev/null 2>&1"; then
    echo "❌ ERROR: Termux not found on device (via /data/data check)."
    echo ""
    echo "Please perform these manual steps on the phone:"
    echo "1. Install Termux from F-Droid."
    echo "2. (Optional) Install Termux:Boot from F-Droid."
    echo "3. Open Termux and run: pkg update && pkg install openssh -y"
    echo "4. Start the SSH server by running: sshd"
    echo ""
    exit 1
fi

if ! adb shell "su -c 'ls -d /data/data/$TERMUX_BOOT_PACKAGE' >/dev/null 2>&1"; then
    echo "⚠️  WARNING: Termux:Boot not found. Automatic start on reboot will not work."
fi

# --- Battery Monitoring Setup ---
adb shell "settings put global battery_tip_show_threshold 85" >/dev/null 2>&1 || true

# --- Power Management & Stability (Cascading Hacks) ---
echo "👻 Hardening background stability and Wi-Fi (Cascading)..."
# 1. Phantom Process Killer (Android 12+)
adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647" >/dev/null 2>&1 || true
adb shell "/system/bin/device_config set_sync_disabled_for_tests persistent" >/dev/null 2>&1 || true
adb shell settings put global settings_enable_monitor_phantom_procs false >/dev/null 2>&1 || true

# 2. Wi-Fi Sleep Policy (Keep alive during sleep)
adb shell settings put global wifi_sleep_policy 2 >/dev/null 2>&1 || adb shell settings put system wifi_sleep_policy 2 >/dev/null 2>&1 || true
adb shell settings put global wifi_idle_ms 86400000 >/dev/null 2>&1 || true

# 3. Doze Mode Exemption for Termux
adb shell dumpsys deviceidle whitelist +com.termux >/dev/null 2>&1 || true

# 4. Screen Timeout Override (Optional/Fallback)
adb shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1 || true

# --- 5. Device-Specific Performance Tuning (aion/Motorola Edge) ---
DEVICE_MODEL=$(adb shell getprop ro.product.model | tr -d '\r' | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')

if [[ "$DEVICE_MODEL" == *"motorolaedge"* ]] || [[ "$DEVICE_MODEL" == *"aion"* ]]; then
    echo "⚡ Motorola Edge 2023 (aion) detected. Applying Performance Profile..."
    
    # Push and run performance-tuning.sh
    DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    if [ -f "$DIR/performance-tuning.sh" ]; then
        adb push "$DIR/performance-tuning.sh" /data/local/tmp/performance-tuning.sh
        adb shell "su -c 'sh /data/local/tmp/performance-tuning.sh && rm /data/local/tmp/performance-tuning.sh'"
    fi

    echo "🧹 Stripping bloatware (aion)..."
    PACKAGES=(
        "com.facebook.services"
        "com.facebook.system"
        "com.facebook.appmanager"
        "com.motorola.brapps"
        "com.motorola.ccc.notification"
        "com.motorola.motocare"
        "com.motorola.genie"
        "com.motorola.aiservices"
        "com.motorola.dimo"
        "com.motorola.securityhub"
        "com.inmobi.weather"
        "com.mobileposse.client"
        "com.aura.oem.monitor"
        "com.digitalturbine.ignoredetector.motorola"
        "com.motorola.msm"
    )

    for pkg in "${PACKAGES[@]}"; do
        # Use pm list packages to check if installed first
        if adb shell "pm list packages | grep -q $pkg"; then
            echo "  - Removing: $pkg"
            adb shell "pm uninstall -k --user 0 $pkg" >/dev/null 2>&1 || true
        fi
    done
fi

echo "💡 NOTE: Please manually verify 'Unrestricted' battery usage for Termux in Android Settings if disconnects persist."

# Get functional role (e.g., matrix-host, scout) from argument
SERVICE_ROLE=${1:-"scout"}
# Siphon hardware ID (e.g., ph-1, s10e) or use provided override
DEVICE_ID=${2:-$(adb shell getprop ro.product.model | tr -d '\r' | tr -cd '[:alnum:]_-' | tr '[:upper:]' '[:lower:]')}
API_LEVEL=$(adb shell getprop ro.build.version.sdk | tr -d '\r')

# The Persona Name is the unique identifier for this specific hardware-role pair
PERSONA_NAME="${SERVICE_ROLE}-${DEVICE_ID}"

echo "🛰️  Provisioning Hardened Rooted Agent: $PERSONA_NAME (API $API_LEVEL)"
echo "📱 Hardware: $DEVICE_ID"
echo "🎭 Role:     $SERVICE_ROLE"

PHONE_IP=$(adb shell "ip addr show wlan0 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" | tr -d '\r')
if [ -z "$PHONE_IP" ]; then
    echo "⚠️  WARNING: Could not detect Phone IP. Bridge may fail."
else
    echo "📶 Found Phone IP: $PHONE_IP"
fi

# 2. Identify Termux User
echo "🔍 Identifying Termux user environment..."
# Robust UID lookup via dumpsys
TERMUX_USER=$(adb shell "dumpsys package com.termux | grep appId=" | head -n 1 | sed 's/.*appId=\([0-9]*\).*/\1/' | tr -d '\r')

if [ -z "$TERMUX_USER" ] || [ "$TERMUX_USER" = "0" ]; then
    # Fallback to filesystem
    TERMUX_USER=$(adb shell "su -c 'ls -ld /data/data/com.termux/files/home'" | awk '{print $3}' | tr -d '\r')
fi

# Convert UID to the u0_aXXX format if it's purely numeric
if [[ "$TERMUX_USER" =~ ^[0-9]+$ ]]; then
    if [ "$TERMUX_USER" -gt 10000 ]; then
        TERMUX_USER="u0_a$((TERMUX_USER - 10000))"
    fi
fi

if [ -z "$TERMUX_USER" ]; then
    echo "❌ ERROR: Could not identify Termux user. Please open the Termux app once on the phone."
    exit 1
fi
echo "👤 Termux User identified as: $TERMUX_USER"

# 3. Verify Termux Prerequisites
echo "📦 Verifying Termux prerequisites..."
if ! adb shell "pgrep sshd >/dev/null 2>&1"; then
    echo "❌ ERROR: SSH server (sshd) is not running in Termux."
    echo "Please open Termux on the phone and run: sshd"
    exit 1
else
    echo "✅ SSH server is active."
fi

# 3b. Configure Termux Wake Lock & Services
echo "🔧 Configuring Termux wake lock & services..."
adb shell "su $TERMUX_USER -g 3003 -c 'PATH=/data/data/com.termux/files/usr/bin:\$PATH /data/data/com.termux/files/usr/bin/pkg install root-repo -y > /dev/null 2>&1 || true'"
adb shell "su $TERMUX_USER -g 3003 -c 'PATH=/data/data/com.termux/files/usr/bin:\$PATH /data/data/com.termux/files/usr/bin/termux-wake-lock || true'"

# Generate services script on host and push it (starts sshd + mounts chroot + starts ollama, no dashboard)
cat << 'EOF' > start-services.sh
#!/data/data/com.termux/files/usr/bin/bash
export PATH="/data/data/com.termux/files/usr/bin:$PATH"

pgrep sshd >/dev/null || sshd

su -c '
    UBUNTU_ROOT="/data/local/ubuntu"
    mount | grep -q "$UBUNTU_ROOT/proc" || mount -t proc proc "$UBUNTU_ROOT/proc"
    mount | grep -q "$UBUNTU_ROOT/sys" || mount -t sysfs sys "$UBUNTU_ROOT/sys"
    mount | grep -q "$UBUNTU_ROOT/dev" || mount --bind /dev "$UBUNTU_ROOT/dev"
    mount | grep -q "$UBUNTU_ROOT/dev/pts" || mount --bind /dev/pts "$UBUNTU_ROOT/dev/pts"
    su -g 3003 -c "chroot /data/local/ubuntu /bin/su - agent-lab -c \"pgrep ollama >/dev/null || (export OLLAMA_HOST=0.0.0.0 && /usr/local/bin/ollama serve > /home/agent-lab/ollama.log 2>&1 &)\""
'
EOF

adb push start-services.sh /data/local/tmp/start-services.sh
rm start-services.sh
adb shell "su -c 'mv /data/local/tmp/start-services.sh $TERMUX_HOME/start-services.sh && chown $TERMUX_USER:$TERMUX_USER $TERMUX_HOME/start-services.sh && chmod +x $TERMUX_HOME/start-services.sh'"

# 3c. Configure Termux:Boot script
echo "🚀 Configuring Termux:Boot startup script..."
adb shell "su -c 'mkdir -p $TERMUX_HOME/.termux/boot && \
                 echo -e \"#!/data/data/com.termux/files/usr/bin/bash\ntermux-wake-lock\nsshd\n~/start-services.sh\" > $TERMUX_HOME/.termux/boot/start-agent && \
                 chown -R $TERMUX_USER:$TERMUX_USER $TERMUX_HOME/.termux && \
                 chmod +x $TERMUX_HOME/.termux/boot/start-agent'"

# 4. Prepare Ubuntu Chroot Environment (Idempotent Ollama binary check)
echo "🧪 Checking Ubuntu Chroot dependencies..."

# 4a. Mount essential filesystems
echo "📁 Mounting filesystems for chroot..."
adb shell "su -c 'mount -t proc proc $UBUNTU_ROOT/proc || true'"
adb shell "su -c 'mount -t sysfs sys $UBUNTU_ROOT/sys || true'"
adb shell "su -c 'mount --bind /dev $UBUNTU_ROOT/dev || true'"
adb shell "su -c 'mount --bind /dev/pts $UBUNTU_ROOT/dev/pts || true'"
adb shell "su -c 'echo nameserver 8.8.8.8 > $UBUNTU_ROOT/etc/resolv.conf'"

# 4b. Base dependencies
# Note: Using 'su -g 3003' to enter chroot with network permissions
adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c \\\"apt update && apt install -y python3-venv python3-pip curl ca-certificates\\\"\"'"

# 4c. Ollama binary check
if adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /usr/local/bin/ollama --version >/dev/null 2>&1\"'"; then
    echo "✅ Ollama binary already exists."
else
    echo "📥 Installing Ollama via official script..."
    # Running the official installer inside the chroot
    adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c \\\"curl -fsSL https://ollama.com/install.sh | sh\\\"\"'"
fi

# 5. Setup Virtual Environment & LLM Tools (Idempotent venv check)
echo "🐍 Checking Python Virtual Environment..."
if adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /bin/su - agent-lab -c \\\"ls ~/venv/bin/activate >/dev/null 2>&1\\\"\"'"; then
    echo "✅ Venv already exists."
else
    echo "🐍 Creating virtual environment and installing llm..."
    adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /bin/su - agent-lab -c \\\"
        python3 -m venv ~/venv && \
        ~/venv/bin/pip install --upgrade pip && \
        ~/venv/bin/pip install llm llm-ollama\\\"\"'"
fi

# 6. Bootstrap Ollama & Models (Idempotent model check)
echo "📥 Checking model $MODEL_NAME..."
# Start ollama if not running (binding to all interfaces for cluster access)
adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /bin/su - agent-lab -c \\\"pgrep ollama >/dev/null || (export OLLAMA_HOST=0.0.0.0 && /usr/local/bin/ollama serve > ~/ollama.log 2>&1 & sleep 5)\\\"\"'"
# Check if model is already pulled
if adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /bin/su - agent-lab -c \\\"/usr/local/bin/ollama list\\\"\"' | grep -q \"$MODEL_NAME\""; then
    echo "✅ Model $MODEL_NAME already pulled."
else
    echo "📥 Pulling model $MODEL_NAME..."
    adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /bin/su - agent-lab -c \\\"export OLLAMA_HOST=0.0.0.0 && /usr/local/bin/ollama pull $MODEL_NAME\\\"\"'"
fi

# 6b. Pre-warm the model so it's in RAM and ready for inference (no cold starts)
if [ -n "$PHONE_IP" ]; then
    echo "🔥 Pre-warming $MODEL_NAME (keep_alive: -1)..."
    curl -s --max-time 300 -X POST "http://$PHONE_IP:11434/api/generate" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL_NAME\", \"prompt\": \"\", \"keep_alive\": -1}" \
        -o /dev/null && echo "✅ Model is loaded and warm." || echo "⚠️  Warmup failed — model will cold-start on first request."
else
    echo "⚠️  Phone IP unknown — skipping warmup. Run set-mobile-model.sh manually after provisioning."
fi

# 7. Deploy Hardened enter-lab.sh
echo "🛡️  Deploying enter-lab.sh dispatcher..."
# Note: Using the current script in our repo (must be in same dir)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
adb push "$DIR/enter-lab.sh" /data/local/tmp/enter_lab.sh
adb shell "su -c 'mv /data/local/tmp/enter_lab.sh $TERMUX_HOME/enter_lab.sh && chown $TERMUX_USER:$TERMUX_USER $TERMUX_HOME/enter_lab.sh && chmod 700 $TERMUX_HOME/enter_lab.sh'"

# 8. Device-Specific Key Management (Using Persona Name)
DEVICE_KEY="$HOME/.ssh/id_mobile_$PERSONA_NAME"
echo "🔑 Managing Device-Specific SSH Key: $DEVICE_KEY"

if [ -f "$DEVICE_KEY" ]; then
    echo "✅ SSH Key for $PERSONA_NAME already exists."
else
    echo "🆕 Generating NEW password-protected key for $PERSONA_NAME..."
    ssh-keygen -t ed25519 -f "$DEVICE_KEY" -N "" -C "agent-lab@$PERSONA_NAME"
fi

# Push the NEW public key to the phone
adb push "${DEVICE_KEY}.pub" /data/local/tmp/mobile_key.pub
echo "🔑 Syncing NEW public key and hardening permissions..."
adb shell "su -c 'mkdir -p $TERMUX_HOME/.ssh && \
                 cat /data/local/tmp/mobile_key.pub > $TERMUX_HOME/.ssh/authorized_keys && \
                 chown -R $TERMUX_USER:$TERMUX_USER $TERMUX_HOME/.ssh && \
                 chmod 700 $TERMUX_HOME/.ssh && \
                 chmod 600 $TERMUX_HOME/.ssh/authorized_keys'"
adb shell "rm /data/local/tmp/mobile_key.pub"

# 9. Register in Kubernetes Cluster
echo "🔗 Bridging phone into k3s cluster as $PERSONA_NAME..."
"$DIR/bridge-phone.sh" "$PHONE_IP" "$SERVICE_ROLE" "$DEVICE_ID"

# 10. Final Verification (Using the NEW specific key and correct Termux user)
echo "✅ Verifying passwordless SSH handoff with NEW key..."
if ssh -i "$DEVICE_KEY" -p 8022 -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes "$TERMUX_USER@$PHONE_IP" "uptime" > /dev/null 2>&1; then
    echo "📶 SSH: VERIFIED (Device-Specific Key)"
else
    echo "⚠️  SSH: MANUAL CHECK REQUIRED (Try: ssh-add $DEVICE_KEY)"
fi
