#!/bin/bash

# ==========================================
# 📱 Mobile Agent Model Query
# ==========================================
# Queries an LLM running on a mobile node via 
# its Ollama API.
# ==========================================

set -e

# Configuration
NAMESPACE="agent-execution"
KUBECONFIG_PATH="$HOME/.kube/k3s-config"

# Usage
usage() {
    echo "❌ Usage: $0 --node <node_name> --query <prompt> [--model <model_name>]"
    echo "Example: $0 --node s20 --query \"Hello!\""
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
for cmd in kubectl curl jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ ERROR: '$cmd' is not installed. Please install it to use this script."
        exit 1
    fi
done

echo "🔍 Resolving IP for node '$NODE'..."

# 1. Resolve IP from K8s Endpoints
export KUBECONFIG="$KUBECONFIG_PATH"
IP=$(kubectl get endpoints "$NODE" -n "$NAMESPACE" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)

if [ -z "$IP" ]; then
    echo "❌ ERROR: Could not find IP for node '$NODE'. Is it bridged?"
    exit 1
fi

# 2. Resolve Model if not provided
if [ -z "$MODEL" ]; then
    echo "🤖 Auto-detecting model..."
    MODEL=$(curl -s "http://$IP:11434/api/tags" | jq -r '.models[0].name' || true)
    
    if [ -z "$MODEL" ] || [ "$MODEL" == "null" ]; then
        echo "❌ ERROR: No models found on $NODE. Use './scripts/set-mobile-model.sh' first."
        exit 1
    fi
fi

echo "🚀 Querying '$MODEL' at $IP..."
echo "------------------------------------------"

# 3. Perform the query (Streaming)
curl -s -N -X POST "http://$IP:11434/api/generate" \
    -d "$(jq -n --arg model "$MODEL" --arg prompt "$QUERY" '{model: $model, prompt: $prompt}')" | \
    while read -r line; do
        # Extract the 'response' field and print it
        echo "$line" | jq -r '.response // ""' | tr -d '\n'
        # Check if we are done
        if [[ $(echo "$line" | jq -r '.done') == "true" ]]; then
            echo "" # Final newline
            break
        fi
    done

echo "------------------------------------------"
