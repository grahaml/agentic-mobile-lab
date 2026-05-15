#!/bin/bash

# ==========================================
# 📱 Mobile Agent Model Swapper
# ==========================================
# Swaps the active LLM on a mobile node by 
# pulling the new model and updating the 
# enter-lab.sh dispatcher.
# ==========================================

set -e

# Binary Checks
for cmd in kubectl ollama; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ ERROR: '$cmd' is not installed or not in PATH."
        exit 1
    fi
done

# Configuration
NAMESPACE="agent-execution"
KUBECONFIG_PATH="$HOME/.kube/k3s-config"

# Usage
usage() {
    echo "❌ Usage: $0 --node <node_name> --model <model_name>"
    echo "Example: $0 --node s20 --model qwen2.5-coder:7b"
    exit 1
}

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --node) NODE="$2"; shift ;;
        --model) MODEL="$2"; shift ;;
        *) usage ;;
    esac
    shift
done

if [ -z "$NODE" ] || [ -z "$MODEL" ]; then
    usage
fi

echo "🔍 Resolving IP for node '$NODE' in namespace '$NAMESPACE'..."

# 1. Resolve IP from K8s Endpoints
export KUBECONFIG="$KUBECONFIG_PATH"
IP=$(kubectl get endpoints "$NODE" -n "$NAMESPACE" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)

if [ -z "$IP" ]; then
    echo "❌ ERROR: Could not find IP for node '$NODE'. Is it bridged?"
    exit 1
fi

echo "📶 Found node '$NODE' at $IP"

# 2. Pull the model using the host's Ollama CLI (directed to the device)
echo "📥 Pulling model '$MODEL' on $NODE..."
if ! OLLAMA_HOST="http://$IP:11434" ollama pull "$MODEL"; then
    echo "❌ ERROR: Failed to pull model via Ollama API at $IP:11434"
    exit 1
fi

# 3. Update enter-lab.sh on the device via SSH
echo "🛡️  Updating 'enter-lab.sh' on $NODE..."

# Identify the SSH key and Termux user
KEY="$HOME/.ssh/id_mobile_$NODE"
if [ ! -f "$KEY" ]; then
    echo "⚠️ Warning: SSH key '$KEY' not found. Trying to guess user..."
    # Fallback to attempting to find ANY mobile key if specific one is missing (though provisioning should have created it)
fi

# We need to find the termux user. We can try to get it from the bridged service metadata or just try a common one.
# During provisioning, the user is often something like u0_aXXX.
# Let's try to get it from the K8s secret if possible, or just attempt SSH with the key.
# Actually, the 'bridge-phone.sh' doesn't store the user in the service, but the provisioners use it.
# Let's try to find the user by looking at the existing SSH config or just asking the device.

# A better way: try to grep the user from the provisioned files or just attempt a generic SSH if possible.
# Most of our provisioners use $TERMUX_USER.
# Let's try to run a command to find the user if we don't know it.

# For now, let's assume the standard 'u0_a' pattern or just try to connect.
# We'll use a trick: SSH into the IP and see who we are.
# But we need a user to SSH in the first place.

# Let's look at how other scripts handle this. 'monitor-battery.sh' uses:
# BATT_DATA=$(ssh -n -o StrictHostKeyChecking=no -o ConnectTimeout=2 -i "$KEY" -p 8022 "$ENDPOINT_IP" ...)
# It seems it might be missing the user@ part or relying on ~/.ssh/config.

# Let's check bridge-phone.sh again. It doesn't save the user.
# provision-rooted-node.sh sets TERMUX_USER=$(adb shell id -u | awk '{print "u0_a" $1-10000}') - wait, no.
# Actually, `adb shell whoami` works.

echo "🔑 Attempting to identify Termux user..."
# We can use adb if the device is connected via USB, but this script is for bridged nodes (network).
# So we rely on the SSH key.

# Let's try to find the user from the SSH key's comment or just try 'agent-lab' (wait, that's inside chroot).
# The SSH server runs in Termux.

# If we don't know the user, let's try to find it in the local-manifests if we stored it there? No.
# Let's try to look for the key in ~/.ssh/config or just try common ones.

# Actually, many of the scripts use a specific key.
# Let's just try to SSH with the key and let SSH handle the user if it's in the config, 
# or we can try to find the user that was used during provisioning.

USER_HINT=$(grep -l "$NODE" mobile-nodes/local-manifests/mobile-bridge-*.yaml | xargs grep "device-id" | awk '{print $2}' || true)

# Better yet, let's just try to SSH to the IP with the key and see if it works without a user (relying on config)
# or try a few likely candidates.

# Let's check if the user is in the known_hosts or something? No.
# I'll just use a generic 'ssh' call and hope the user has it in their config, 
# or I'll try to find the user from the provision-*.sh scripts if they were run recently.

# Wait, the `provision-*.sh` scripts create the key. Let's see where they put the user.
# provision-rooted-node.sh:
# TERMUX_USER=$(adb shell whoami)
# DEVICE_KEY="$HOME/.ssh/id_mobile_$PERSONA_NAME"

# I'll add a check to try and find the user if possible.
TERMUX_USER=$(ssh-add -L | grep "$NODE" | awk '{print $3}' | cut -d'@' -f1 || echo "")

if [ -z "$TERMUX_USER" ]; then
    # Try to find it in ~/.ssh/config
    TERMUX_USER=$(grep -B 5 "$NODE" ~/.ssh/config 2>/dev/null | grep "User " | awk '{print $2}' | head -n 1 || echo "")
fi

if [ -z "$TERMUX_USER" ]; then
    echo "❓ Could not automatically determine Termux user for $NODE."
    read -p "Please enter the Termux user (e.g., u0_a123): " TERMUX_USER
fi

echo "🚀 Connecting to $TERMUX_USER@$IP..."

# Perform the swap in enter-lab.sh
# We need to escape the model name for sed
ESC_MODEL=$(echo "$MODEL" | sed 's/[:\/]/\\&/g')

ssh -i "$KEY" -p 8022 -o StrictHostKeyChecking=no "$TERMUX_USER@$IP" "
    if [ -f ~/enter-lab.sh ]; then
        echo 'Updating enter-lab.sh...'
        # Update llm command
        sed -i 's/llm -m [^ ]*/llm -m $ESC_MODEL/' ~/enter-lab.sh
        # Update ollama pull command in update action
        sed -i 's/ollama pull [^ \"]*/ollama pull $ESC_MODEL/' ~/enter-lab.sh
        echo '✅ Update complete.'
    else
        echo '❌ Error: ~/enter-lab.sh not found on device.'
        exit 1
    fi
"

echo "✨ Model swap complete! Node '$NODE' is now using '$MODEL'."
