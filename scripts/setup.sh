#!/bin/bash

# ==========================================
# Modernized Private Agent Runtime Setup
# Focus: Persistence, High-Memory, and High-Context
# ==========================================

set -euo pipefail

# --- Parse Arguments ---
WITH_OLLAMA=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-ollama)
            WITH_OLLAMA=true
            shift
            ;;
        *)
            echo "❌ Unknown argument: $1"
            echo "Usage: $0 [--with-ollama]"
            exit 1
            ;;
    esac
done

# --- Configuration ---
K3S_KUBECONFIG="$HOME/.kube/k3s-config" # Dedicated path for this cluster
export KUBECONFIG="$K3S_KUBECONFIG"    # Force kubectl to use this file only

NAMESPACE_AGENTS="agent-execution"
NAMESPACE_OLLAMA="ollama-system"
MODEL_NAME="qwen2.5-coder:7b"
OLLAMA_IMAGE="ollama/ollama:0.5.11" # Pinned to current stable version

if [ "$WITH_OLLAMA" = true ]; then
    echo "🚀 Starting Persistent Private Agent Runtime Installation (WITH Ollama)..."
else
    echo "🚀 Starting Persistent Private Agent Runtime Installation (WITHOUT Ollama - using external inference)..."
fi

# ==========================================
# 1. k3s Installation & Isolated Config Sync
# ==========================================
if ! command -v k3s &> /dev/null; then
    echo "🛠️  k3s not found. Installing k3s..."
    curl -sfL https://get.k3s.io | sh -

    # Wait for k3s to be ready
    echo "⏳ Waiting for k3s to start (30 seconds)..."
    sleep 30

    # Verify installation
    if ! command -v k3s &> /dev/null; then
        echo "❌ Error: k3s installation failed"
        exit 1
    fi
    echo "✅ k3s installed successfully"
else
    echo "✅ k3s already installed"
fi

# Sync the config to our dedicated, isolated file
echo "🔑 Syncing isolated k3s access to $K3S_KUBECONFIG..."
mkdir -p "$HOME/.kube"

# Wait for k3s config to be available
if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
    echo "⏳ Waiting for k3s config to be generated..."
    sleep 10
fi

sudo cp /etc/rancher/k3s/k3s.yaml "$K3S_KUBECONFIG"
sudo chown $(id -u):$(id -g) "$K3S_KUBECONFIG"
chmod 600 "$K3S_KUBECONFIG"

# Verify kubectl is working
echo "🔍 Verifying kubectl access..."
if ! kubectl get nodes &> /dev/null; then
    echo "⏳ Waiting for k3s control plane to be ready..."
    sleep 10
fi

# Use standard kubectl (automatically points to $KUBECONFIG)
KUBECMD="kubectl"

echo "✅ k3s cluster ready"

# ==========================================
# 2. Namespaces & Storage
# ==========================================
echo "🛡️  Configuring Namespaces & Storage..."

if [ "$WITH_OLLAMA" = true ]; then
    $KUBECMD create namespace "$NAMESPACE_OLLAMA" --dry-run=client -o yaml | $KUBECMD apply -f -
    echo "   Created $NAMESPACE_OLLAMA namespace"

    # Create a 20GB Persistent Volume Claim for models using k3s default local-path provisioner
    $KUBECMD apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ollama-models-pvc
  namespace: $NAMESPACE_OLLAMA
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
EOF
    echo "   Created ollama-models-pvc (20Gi)"
else
    echo "   (Skipping Ollama storage - using external inference)"
fi

$KUBECMD create namespace "$NAMESPACE_AGENTS" --dry-run=client -o yaml | $KUBECMD apply -f -
echo "   Created $NAMESPACE_AGENTS namespace"

# ==========================================
# 3. Deploy Ollama (Conditional)
# ==========================================
if [ "$WITH_OLLAMA" = true ]; then
    echo "🧠 Deploying Ollama ($OLLAMA_IMAGE) with 10Gi limit..."

    $KUBECMD apply -f - <<EOF
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
        image: $OLLAMA_IMAGE
        ports:
        - containerPort: 11434
        resources:
          requests:
            cpu: "1"
            memory: "4Gi"
          limits:
            cpu: "2"
            memory: "10Gi"
        volumeMounts:
        - name: model-storage
          mountPath: /root/.ollama
      volumes:
      - name: model-storage
        persistentVolumeClaim:
          claimName: ollama-models-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: ollama-service
  namespace: $NAMESPACE_OLLAMA
spec:
  type: ClusterIP
  selector:
    app: ollama
  ports:
    - protocol: TCP
      port: 11434
      targetPort: 11434
EOF

    echo "⏳ Waiting for Ollama pod to be Ready..."
    $KUBECMD rollout status deployment/ollama -n "$NAMESPACE_OLLAMA" --timeout=120s

    # ==========================================
    # 4. Pull and Create High-Context Preset
    # ==========================================
    echo "📥 Pulling $MODEL_NAME (this will only happen if not already in Volume)..."
    $KUBECMD exec -n "$NAMESPACE_OLLAMA" deploy/ollama -- ollama pull "$MODEL_NAME"

    echo "⚙️  Configuring high-context preset (qwen-large-ctx)..."
    $KUBECMD exec -n "$NAMESPACE_OLLAMA" deploy/ollama -- bash -c "echo 'FROM $MODEL_NAME
PARAMETER num_ctx 32768' > Modelfile && ollama create qwen-large-ctx -f Modelfile"

    echo "=========================================="
    echo "✅ PERSISTENT SETUP COMPLETE (WITH LOCAL OLLAMA)"
    echo "Model: $MODEL_NAME (32k Context Preset Ready)"
    echo "Isolated Config: $K3S_KUBECONFIG"
    echo "Ollama Memory Limit: 10Gi"
    echo "=========================================="
else
    echo "📡 Skipping local Ollama deployment (using external inference)"
    echo "=========================================="
    echo "✅ PERSISTENT SETUP COMPLETE (EXTERNAL INFERENCE)"
    echo "Agent Namespace: $NAMESPACE_AGENTS"
    echo "Isolated Config: $K3S_KUBECONFIG"
    echo "Configure agents to reach external LLM at: \$LLM_SERVER_URL"
    echo "=========================================="
fi
