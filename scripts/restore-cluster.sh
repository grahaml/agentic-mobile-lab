#!/bin/bash

# ==========================================
# 🔄 Private Agent Runtime Restore Script
# ==========================================
# This script re-provisions the k3s cluster and 
# redeploys all applications from backed-up manifests.
# ==========================================

set -euo pipefail

K3S_KUBECONFIG="$HOME/.kube/k3s-config"
export KUBECONFIG="$K3S_KUBECONFIG"

echo "🚀 Starting Cluster Restoration..."

# 1. k3s Installation Check
if ! command -v k3s &> /dev/null; then
    echo "📦 Installing k3s..."
    curl -sfL https://get.k3s.io | sh -
fi

# 2. Sync Kubeconfig
echo "🔑 Syncing k3s config..."
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$K3S_KUBECONFIG"
sudo chown $(id -u):$(id -g) "$K3S_KUBECONFIG"
chmod 600 "$K3S_KUBECONFIG"

# 3. Build Local Images
echo "🛠️  Building local images..."
if [ -d "fleet-mcp" ] && command -v docker &> /dev/null; then
    docker build -t fleet-mcp:latest fleet-mcp/
    docker save fleet-mcp:latest | sudo k3s ctr images import -
else
    echo "⚠️  Skipping fleet-mcp build (docker not found or fleet-mcp dir missing)."
fi

# 4. Create Namespaces
echo "🛡️ Creating Namespaces..."
kubectl create namespace hermes-sandbox --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ollama-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace agent-execution --dry-run=client -o yaml | kubectl apply -f -

# 4. Apply Core Infrastructure
echo "🏗️ Applying RBAC and Network Policies..."
kubectl apply -f manifests/agent-executor-rbac.yaml
kubectl apply -f manifests/netpol-allow-internal.yaml

# 5. Apply Application Manifests
echo "📱 Applying Application Manifests..."
kubectl apply -f manifests/ollama-system.yaml
kubectl apply -f manifests/hermes-sandbox.yaml
kubectl apply -f manifests/agent-execution-services.yaml
kubectl apply -f manifests/fleet-mcp-deployment.yaml

# 6. Apply Ingress (if needed)
echo "🌐 Applying Ingress rules..."
kubectl apply -f manifests/fleet-mcp-ingress.yaml || echo "⚠️ Fleet MCP Ingress failed (might need Traefik to settle)"
kubectl apply -f manifests/gateway-mcp-ingress.yaml || echo "⚠️ Gateway Ingress failed"

# 7. Wait for Ollama and Pull Models
echo "🧠 Waiting for Ollama to be ready..."
kubectl rollout status deployment/ollama -n ollama-system --timeout=120s || echo "⚠️ Ollama rollout timed out"

echo "📥 Pulling models (qwen2.5-coder:7b)..."
kubectl exec -n ollama-system deploy/ollama -- ollama pull qwen2.5-coder:7b || echo "⚠️ Failed to pull model"

echo "⚙️ Configuring high-context preset (qwen-large-ctx)..."
kubectl exec -n ollama-system deploy/ollama -- bash -c "echo 'FROM qwen2.5-coder:7b
PARAMETER num_ctx 32768' > Modelfile && ollama create qwen-large-ctx -f Modelfile" || echo "⚠️ Failed to create preset"

echo "=========================================="
echo "✅ RESTORATION ATTEMPT COMPLETE"
echo "Note: Secrets were NOT backed up. You must recreate them manually."
echo "Specifically: 'hermes-secrets', 'hermes-programmer-secrets', and 'hermes-specialist-secrets' in hermes-sandbox."
echo "And '*-ssh-key' secrets for mobile nodes if you haven't re-run bridge-phone.sh."
echo "=========================================="
