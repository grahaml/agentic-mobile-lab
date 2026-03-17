#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status

# ==========================================
# Configuration
# ==========================================
CLUSTER_NAME="agent-sandbox"
NAMESPACE_AGENTS="agent-execution"
NAMESPACE_OLLAMA="ollama-system"
MODEL_NAME="qwen2.5:0.5b" # CPU-friendly model

echo "🚀 Starting Local AI Swarm Installation for Ubuntu..."

# ==========================================
# 1. Pre-flight Checks (Linux Native)
# ==========================================
echo "🔍 Checking dependencies..."

if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed."
    echo "Run: curl -fsSL https://get.docker.com | sudo sh"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed."
    echo "Run: sudo snap install kubectl --classic"
    exit 1
fi

if ! command -v k3d &> /dev/null; then
    echo "❌ Error: k3d is not installed."
    echo "Run: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
    exit 1
fi

echo "✅ All dependencies found."

# ==========================================
# 2. Cluster Bootstrap (with Native Port Mapping)
# ==========================================
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
    echo "⚠️  Cluster '$CLUSTER_NAME' already exists. Skipping creation."
else
    echo "📦 Spinning up K3d cluster: $CLUSTER_NAME (with NetworkPolicy support)..."
    # Enable the k3s integrated network policy controller
    k3d cluster create "$CLUSTER_NAME" \
        -p "11434:11434@loadbalancer" \
        --k3s-arg "--disable-network-policy=false@server:*" \
        --servers 1 --agents 0 --wait
    echo "✅ Cluster created."
fi

# ==========================================
# 3. Secure Namespaces & Network Policies
# ==========================================
echo "🛡️  Configuring namespaces and sandboxed network policies..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE_OLLAMA
---
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE_AGENTS
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: $NAMESPACE_AGENTS
spec:
  podSelector: {}
  policyTypes:
  - Egress
EOF
echo "✅ Sandboxed namespaces created."

# ==========================================
# 4. Deploy CPU-Optimized Ollama
# ==========================================
echo "🧠 Deploying Ollama (Native Linux CPU mode)..."

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ollama
  namespace: $NAMESPACE_OLLAMA
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ollama
  template:
    metadata:
      labels:
        app: ollama
    spec:
      containers:
      - name: ollama
        image: ollama/ollama:latest
        ports:
        - containerPort: 11434
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: ollama-service
  namespace: $NAMESPACE_OLLAMA
spec:
  type: LoadBalancer 
  selector:
    app: ollama
  ports:
    - protocol: TCP
      port: 11434
      targetPort: 11434
EOF

echo "⏳ Waiting for Ollama pod to be ready (this might take a minute)..."
kubectl rollout status deployment/ollama -n $NAMESPACE_OLLAMA --timeout=120s

# ==========================================
# 5. Pulling the Local Model
# ==========================================
echo "📥 Pulling $MODEL_NAME directly into the cluster..."
OLLAMA_POD=$(kubectl get pods -n $NAMESPACE_OLLAMA -l app=ollama -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NAMESPACE_OLLAMA $OLLAMA_POD -- ollama run $MODEL_NAME "Initialization complete."

# ==========================================
# 6. Install Aider (in Virtual Environment)
# ==========================================
VENV_DIR="$HOME/.venv-private-runtime"

if [ -d "$VENV_DIR" ]; then
    echo "🗑️ Removing old virtual environment..."
    rm -rf "$VENV_DIR"
fi

echo "📦 Creating virtual environment for Aider at $VENV_DIR using python3..."
python3 -m venv "$VENV_DIR"

echo "📦 Installing/Updating Aider in virtual environment..."
"$VENV_DIR/bin/pip" install -U pip aider-chat

echo "=========================================="
echo "🎉 INFRASTRUCTURE READY! 🎉"
echo "=========================================="
echo "To launch Aider connected to your private K3d cluster, run:"
echo ""
echo "  source $VENV_DIR/bin/activate"
echo "  aider --model ollama/$MODEL_NAME"
echo ""
echo "Or use the direct path:"
echo "  $VENV_DIR/bin/aider --model ollama/$MODEL_NAME"
echo ""
echo "Note: If using a custom Ollama host, set OLLAMA_API_BASE=\"http://localhost:11434/v1\""