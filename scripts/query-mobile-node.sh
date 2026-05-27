#!/bin/bash

# ==========================================
# 📱 Mobile Agent Model Query
# ==========================================
# Queries an LLM running on a mobile node via
# its Ollama API.
#
# Updated 2026-05-27: Works with direct
# network IPs (no k8s bridging required)
# ==========================================

set -e

# Configuration: Node name → IP mapping
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
    echo "❌ Usage: $0 --node <node_name> --query <prompt> [--model <model_name>]"
    echo ""
    echo "Available nodes:"
    for node in "${!NODE_IPS[@]}"; do
        echo "  $node (${NODE_IPS[$node]})"
    done | sort -u
    echo ""
    echo "Example: $0 --node moto2023 --query \"Hello!\""
    echo "Example: $0 --node moto2023 --query \"Sum 5+3\" --model qwen2.5-coder:7b"
    exit 1
}

# Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --node) NODE="$2"; shift ;;
        --query) QUERY="$2"; shift ;;
        --model) MODEL="$2"; shift ;;
        *) usage ;;
    esac
    shift
done

if [ -z "$NODE" ] || [ -z "$QUERY" ]; then
    usage
fi

# Binary Checks
for cmd in curl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ ERROR: '$cmd' is not installed. Please install it to use this script."
        exit 1
    fi
done

# Resolve node name to IP
if [ -z "${NODE_IPS[$NODE]}" ]; then
    echo "❌ ERROR: Unknown node '$NODE'"
    usage
fi

IP="${NODE_IPS[$NODE]}"

echo "🔍 Resolving node '$NODE' at $IP..."

# 2. Resolve Model if not provided
if [ -z "$MODEL" ]; then
    echo "🤖 Auto-detecting model..."
    MODEL=$(curl -s "http://$IP:11434/api/tags" | jq -r '.models[0].name' || true)
    
    if [ -z "$MODEL" ] || [ "$MODEL" == "null" ]; then
        echo "❌ ERROR: No models found on $NODE. Use './scripts/set-mobile-model.sh' first."
        exit 1
    fi
fi

echo "🚀 Querying '$MODEL' at http://$IP:11434"
echo "=================================================="
echo ""

# 3. Perform the query (non-streaming for stats)
start_time=$(date +%s%N)

response=$(curl -s -X POST "http://$IP:11434/api/generate" \
    -d "$(jq -n --arg model "$MODEL" --arg prompt "$QUERY" '{model: $model, prompt: $prompt, stream: false}')")

end_time=$(date +%s%N)
elapsed_ms=$(( (end_time - start_time) / 1000000 ))

echo "📝 Response:"
echo "$response" | jq -r '.response'
echo ""
echo "📊 Performance Stats:"
echo "  Total time: ${elapsed_ms}ms"
echo "$response" | jq '{eval_count, eval_duration: .eval_duration/1000000, prompt_eval_count, prompt_eval_duration: .prompt_eval_duration/1000000}' | sed 's/^/  /'
echo ""
echo "=================================================="
