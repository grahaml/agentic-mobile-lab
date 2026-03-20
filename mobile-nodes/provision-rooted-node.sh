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

if ! adb shell pm list packages | grep -q "package:$TERMUX_PACKAGE"; then
    echo "❌ ERROR: Termux not found on device."
    echo ""
    echo "Please perform these manual steps on the phone:"
    echo "1. Install Termux from F-Droid."
    echo "2. (Optional) Install Termux:Boot from F-Droid."
    echo "3. Open Termux and run: pkg update && pkg install openssh -y"
    echo "4. Start the SSH server by running: sshd"
    echo ""
    exit 1
fi

if ! adb shell pm list packages | grep -q "package:$TERMUX_BOOT_PACKAGE"; then
    echo "⚠️  WARNING: Termux:Boot not found. Automatic start on reboot will not work."
fi

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

# 2. Get Termux User (Requires su to see Termux's private dir)
TERMUX_USER=$(adb shell "su -c 'ls -ld $TERMUX_HOME'" | awk '{print $3}' | tr -d '\r')
echo "👤 Termux User identified as: $TERMUX_USER"

# 3. Install Termux Dependencies (Idempotent pkg check)
TERMUX_BIN="/data/data/com.termux/files/usr/bin"
echo "📦 Checking Termux dependencies..."
# Check if sshd is already in the bin folder
# Note: Using -g 3003 (inet) for all Termux user commands to ensure network access on Android 15
if adb shell "su -c 'ls $TERMUX_BIN/sshd >/dev/null 2>&1'"; then
    echo "✅ SSH already installed in Termux."
else
    echo "📦 Installing OpenSSH..."
    adb shell "su -c 'PATH=$TERMUX_BIN:\$PATH $TERMUX_BIN/pkg update -y && PATH=$TERMUX_BIN:\$PATH $TERMUX_BIN/pkg install openssh -y'"
fi
# Always ensure sshd is running
adb shell "su -c 'pgrep sshd >/dev/null || $TERMUX_BIN/sshd'"

# 3b. Configure Termux Dashboard & Wake Lock
echo "🪟 Configuring Termux Dashboard & Wake Lock..."
adb shell "su $TERMUX_USER -g 3003 -c 'PATH=$TERMUX_BIN:\$PATH $TERMUX_BIN/pkg install tmux htop -y > /dev/null 2>&1'"
adb shell "su $TERMUX_USER -g 3003 -c 'PATH=$TERMUX_BIN:\$PATH $TERMUX_BIN/termux-wake-lock || true'"

# Generate dashboard script on host and push it
cat << 'EOF' > start-dashboard.sh
#!/data/data/com.termux/files/usr/bin/bash
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
tmux new-session -d -s agent-dashboard

# Split vertically
tmux split-window -v -p 30 -t agent-dashboard:0
# Split bottom pane horizontally
tmux split-window -h -p 50 -t agent-dashboard:0.1

# Top pane (0): htop
tmux send-keys -t agent-dashboard:0.0 "htop" C-m

# Bottom-left pane (1): Chroot processes or Ollama logs
tmux send-keys -t agent-dashboard:0.1 "su -c 'chroot /data/local/ubuntu /bin/su - agent-lab -c \"top\"'" C-m

# Bottom-right pane (2): Readiness
tmux send-keys -t agent-dashboard:0.2 "echo 'Rooted Dashboard Ready!'; ifconfig | grep -E 'inet .*wlan'" C-m

# Attach to session
tmux attach-session -t agent-dashboard
EOF

adb push start-dashboard.sh /data/local/tmp/start-dashboard.sh
rm start-dashboard.sh
adb shell "su -c 'mv /data/local/tmp/start-dashboard.sh $TERMUX_HOME/start-dashboard.sh && chown $TERMUX_USER:$TERMUX_USER $TERMUX_HOME/start-dashboard.sh && chmod +x $TERMUX_HOME/start-dashboard.sh'"

# Auto-launch on open
adb shell "su -c 'grep -q start-dashboard.sh $TERMUX_HOME/.bashrc 2>/dev/null || echo -e \"\n# Auto-start dashboard\nif [ -z \\\"\$TMUX\\\" ]; then\n    ~/start-dashboard.sh\nfi\" >> $TERMUX_HOME/.bashrc'"

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
adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /bin/su - agent-lab -c \\\"pgrep ollama >/dev/null || (export OLLAMA_HOST=0.0.0.0 && /usr/local/bin/ollama serve > /dev/null 2>&1 & sleep 5)\\\"\"'"
# Check if model is already pulled
if adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /bin/su - agent-lab -c \\\"/usr/local/bin/ollama list\\\"\"' | grep -q \"$MODEL_NAME\""; then
    echo "✅ Model $MODEL_NAME already pulled."
else
    echo "📥 Pulling model $MODEL_NAME..."
    adb shell "su -c 'su -g 3003 -c \"chroot $UBUNTU_ROOT /bin/su - agent-lab -c \\\"export OLLAMA_HOST=0.0.0.0 && /usr/local/bin/ollama pull $MODEL_NAME\\\"\"'"
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
