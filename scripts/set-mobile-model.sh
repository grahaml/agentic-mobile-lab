#!/bin/bash

# ==========================================
# 📱 Mobile Agent Model Swapper
# ==========================================
# Swaps the active LLM on a mobile node by
# pulling the new model and updating the
# enter-lab.sh dispatcher.
#
# Updated 2026-05-27: Works with direct
# network IPs (no k8s bridging required)
# ==========================================

set -e

# Binary Checks
if ! command -v ollama &> /dev/null; then
    echo "❌ ERROR: 'ollama' is not installed or not in PATH."
    exit 1
fi

# Configuration: Node name → IP mapping
# Users are auto-detected from each device
declare -A NODE_IPS=(
    ["moto2023"]="10.0.0.30"
    ["s10e"]="10.0.0.10"
    ["s20fe"]="10.0.0.20"
    ["moto"]="10.0.0.30"       # Alias
    ["s10e"]="10.0.0.10"       # Alias
    ["s20"]="10.0.0.20"        # Alias
)

# Usage
usage() {
    echo "❌ Usage: $0 --node <node_name> --model <model_name>"
    echo ""
    echo "Available nodes:"
    for node in "${!NODE_IPS[@]}"; do
        echo "  $node (${NODE_IPS[$node]})"
    done
    echo ""
    echo "Example: $0 --node moto2023 --model qwen2.5-coder:7b"
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

# Resolve node name to IP
if [ -z "${NODE_IPS[$NODE]}" ]; then
    echo "❌ ERROR: Unknown node '$NODE'"
    usage
fi

IP="${NODE_IPS[$NODE]}"

echo "🔍 Resolving node '$NODE' at $IP..."

# Find SSH key (try multiple naming patterns)
KEY=""
ssh_key_candidates=(
    "$HOME/.ssh/id_mobile_${NODE}"
    "$HOME/.ssh/id_mobile_scout-${NODE}"
    "$HOME/.ssh/id_mobile_${NODE}*"
    "$HOME/.ssh/id_mobile_moto*"
    "$HOME/.ssh/id_mobile_s10e*"
    "$HOME/.ssh/id_mobile_s20*"
    "$HOME/.ssh/id_mobile_scout*"
)

for pattern in "${ssh_key_candidates[@]}"; do
    # Use find to match patterns
    found_key=$(find "$HOME/.ssh" -maxdepth 1 -name "$(basename "$pattern")" ! -name "*.pub" 2>/dev/null | head -1)
    if [ -n "$found_key" ]; then
        KEY="$found_key"
        break
    fi
done

if [ -z "$KEY" ]; then
    echo "❌ ERROR: SSH key not found for '$NODE'"
    echo "   Available keys:"
    ls "$HOME/.ssh/id_mobile_*" 2>/dev/null | grep -v ".pub" | sed 's/^/     /' || echo "     (none found)"
    exit 1
fi

# Auto-detect the Termux user by querying the device
echo "🔑 Auto-detecting Termux user on $NODE..."
TERMUX_USER=$(ssh -i "$KEY" -p 8022 -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$IP" "whoami" 2>/dev/null || true)

if [ -z "$TERMUX_USER" ]; then
    echo "❌ ERROR: Could not detect Termux user on $NODE"
    echo "   Make sure SSH is running on the device (sshd)"
    exit 1
fi

echo "📶 Found node '$NODE' at $IP (user: $TERMUX_USER)"

# 2. Pull the model using the host's Ollama CLI (directed to the device)
echo "📥 Pulling model '$MODEL' on $NODE..."
if ! OLLAMA_HOST="http://$IP:11434" ollama pull "$MODEL"; then
    echo "❌ ERROR: Failed to pull model via Ollama API at $IP:11434"
    exit 1
fi

# 2b. Pre-warm the model so it's in RAM and ready for inference (no cold starts)
echo "🔥 Pre-warming '$MODEL' (keep_alive: -1)..."
curl -s --max-time 300 -X POST "http://$IP:11434/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$MODEL\", \"prompt\": \"\", \"keep_alive\": -1}" \
    -o /dev/null
echo "✅ Model '$MODEL' is loaded and warm."

# 3. Update enter-lab.sh on the device via SSH (if it exists)
echo "🛡️  Checking for enter-lab.sh on $NODE..."

echo "🚀 Connecting to $TERMUX_USER@$IP..."

# Perform the swap in enter-lab.sh
# We need to escape the model name for sed
ESC_MODEL=$(echo "$MODEL" | sed 's/[:\/]/\\&/g')

ssh -i "$KEY" -p 8022 -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$TERMUX_USER@$IP" "
    if [ -f ~/enter-lab.sh ]; then
        echo '📝 Updating enter-lab.sh...'
        # Update llm command
        sed -i 's/llm -m [^ ]*/llm -m $ESC_MODEL/' ~/enter-lab.sh
        # Update ollama pull command in update action
        sed -i 's/ollama pull [^ \"]*/ollama pull $ESC_MODEL/' ~/enter-lab.sh
        echo '✅ Updated enter-lab.sh'
    else
        echo '⏭️  enter-lab.sh not found (expected for native Termux setups)'
    fi

    # Verify the model is loaded
    echo '🔍 Verifying model...'
    ollama list | grep '$MODEL' || echo '⚠️  Model may still be loading...'
" 2>&1

echo ""
echo "✨ Model swap complete! Node '$NODE' is now using '$MODEL'."
echo "   Accessible at: http://$IP:11434"
