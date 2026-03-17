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
SERVICE_NAME="mobile-scout" # The "Persona" name for this node

echo "🛰️  Starting Mobile Agent Provisioning ($SERVICE_NAME)..."

# 1. Connectivity Check
if ! adb devices | grep -q "device$"; then
    echo "❌ ERROR: No device found via ADB. Is it connected?"
    exit 1
fi

PHONE_IP=$(adb shell "ip addr show wlan0 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1" | tr -d '\r')
echo "📶 Found Phone IP: $PHONE_IP"

# 2. Get Termux User (Requires su to see Termux's private dir)
TERMUX_USER=$(adb shell "su -c 'ls -ld $TERMUX_HOME'" | awk '{print $3}' | tr -d '\r')
echo "👤 Termux User identified as: $TERMUX_USER"

# 3. Install Termux Dependencies (Idempotent pkg check)
TERMUX_BIN="/data/data/com.termux/files/usr/bin"
echo "📦 Checking Termux dependencies..."
# Check if sshd is already in the bin folder
if adb shell "su $TERMUX_USER -c 'ls $TERMUX_BIN/sshd >/dev/null 2>&1'"; then
    echo "✅ SSH already installed in Termux."
else
    echo "📦 Installing OpenSSH..."
    adb shell "su $TERMUX_USER -c 'PATH=\$PATH:$TERMUX_BIN $TERMUX_BIN/pkg update -y && PATH=\$PATH:$TERMUX_BIN $TERMUX_BIN/pkg install openssh -y'"
fi
# Always ensure sshd is running
adb shell "su $TERMUX_USER -c 'pgrep sshd >/dev/null || $TERMUX_BIN/sshd'"

# 4. Prepare Ubuntu Chroot Environment (Idempotent Ollama binary check)
echo "🧪 Checking Ubuntu Chroot dependencies..."
# 4a. Base dependencies
adb shell "su -c 'chroot $UBUNTU_ROOT /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c \"apt update && apt install -y python3-venv python3-pip curl ca-certificates\"'"

# 4b. Ollama binary check
if adb shell "su -c 'chroot $UBUNTU_ROOT ls /usr/bin/ollama >/dev/null 2>&1'"; then
    echo "✅ Ollama binary already exists."
else
    echo "📥 Downloading Ollama arm64 binary..."
    adb shell "su -c 'chroot $UBUNTU_ROOT /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /bin/bash -c \"curl -L https://ollama.com/download/ollama-linux-arm64 -o /usr/bin/ollama && chmod +x /usr/bin/ollama\"'"
fi

# 5. Setup Virtual Environment & LLM Tools (Idempotent venv check)
echo "🐍 Checking Python Virtual Environment..."
if adb shell "su -c 'chroot $UBUNTU_ROOT /bin/su - agent-lab -lc \"ls ~/venv/bin/activate >/dev/null 2>&1\"'"; then
    echo "✅ Venv already exists."
else
    echo "🐍 Creating virtual environment and installing llm..."
    adb shell "su -c 'chroot $UBUNTU_ROOT /bin/su - agent-lab -c \"
        python3 -m venv ~/venv && \
        ~/venv/bin/pip install --upgrade pip && \
        ~/venv/bin/pip install llm llm-ollama\"'"
fi

# 6. Bootstrap Ollama & Models (Idempotent model check)
echo "📥 Checking model $MODEL_NAME..."
# Start ollama if not running
adb shell "su -c 'chroot $UBUNTU_ROOT /bin/su - agent-lab -c \"pgrep ollama >/dev/null || (ollama serve >/dev/null 2>&1 & sleep 5)\"'"
# Check if model is already pulled
if adb shell "su -c 'chroot $UBUNTU_ROOT /bin/su - agent-lab -c \"ollama list\"' | grep -q \"$MODEL_NAME\""; then
    echo "✅ Model $MODEL_NAME already pulled."
else
    echo "📥 Pulling model $MODEL_NAME..."
    adb shell "su -c 'chroot $UBUNTU_ROOT /bin/su - agent-lab -c \"ollama pull $MODEL_NAME\"'"
fi

# 7. Deploy Hardened enter-lab.sh
echo "🛡️  Deploying enter-lab.sh dispatcher..."
# Note: Using the current script in our repo (must be in same dir)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
adb push "$DIR/enter-lab.sh" /sdcard/enter_lab.sh
adb shell "su -c 'mv /sdcard/enter_lab.sh $TERMUX_HOME/enter_lab.sh && chown $TERMUX_USER:$TERMUX_USER $TERMUX_HOME/enter_lab.sh && chmod 700 $TERMUX_HOME/enter_lab.sh'"

# 8. Device-Specific Key Management (Using Persona Name)
DEVICE_KEY="$HOME/.ssh/id_mobile_$SERVICE_NAME"
echo "🔑 Managing Device-Specific SSH Key: $DEVICE_KEY"

if [ -f "$DEVICE_KEY" ]; then
    echo "✅ SSH Key for $SERVICE_NAME already exists."
else
    echo "🆕 Generating NEW password-protected key for $SERVICE_NAME..."
    ssh-keygen -t ed25519 -f "$DEVICE_KEY" -C "agent-lab@$SERVICE_NAME"
fi

# Push the NEW public key to the phone
PUB_KEY=$(cat "${DEVICE_KEY}.pub")
echo "🔑 Syncing NEW public key and hardening permissions..."
adb shell "su -c 'mkdir -p $TERMUX_HOME/.ssh && \
                 echo \"$PUB_KEY\" > $TERMUX_HOME/.ssh/authorized_keys && \
                 chown -R $TERMUX_USER:$TERMUX_USER $TERMUX_HOME/.ssh && \
                 chmod 700 $TERMUX_HOME/.ssh && \
                 chmod 600 $TERMUX_HOME/.ssh/authorized_keys'"

# 9. SSH Reliability Suite (Macbuntu Side)
echo "🛡️  Ensuring SSH Trust on Macbuntu..."
ssh-keygen -R "[$PHONE_IP]:8022" > /dev/null 2>&1 || true
ssh-keyscan -p 8022 "$PHONE_IP" >> ~/.ssh/known_hosts 2>/dev/null

# 10. Register in Kubernetes Cluster
echo "🔗 Bridging phone into k3d cluster..."
"$DIR/bridge-phone.sh" "$PHONE_IP"

# 11. Final Verification (Using the NEW specific key and correct Termux user)
echo "✅ Verifying passwordless SSH handoff with NEW key..."
if ssh -i "$DEVICE_KEY" -p 8022 -o ConnectTimeout=5 -o BatchMode=yes "$TERMUX_USER@$PHONE_IP" "uptime" > /dev/null 2>&1; then
    echo "📶 SSH: VERIFIED (Device-Specific Key)"
else
    echo "⚠️  SSH: MANUAL CHECK REQUIRED (Try: ssh-add $DEVICE_KEY)"
fi
