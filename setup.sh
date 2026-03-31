#!/bin/bash

# ==========================================
# Modernized Private Agent Runtime Setup
# Focus: Persistence, High-Memory, and High-Context
# ==========================================

set -euo pipefail 

# --- Configuration ---
K3S_KUBECONFIG="$HOME/.kube/k3s-config" # Dedicated path for this cluster
export KUBECONFIG="$K3S_KUBECONFIG"    # Force kubectl to use this file only

NAMESPACE_AGENTS="agent-execution"
NAMESPACE_OLLAMA="ollama-system"
MODEL_NAME="qwen2.5-coder:7b" 
OLLAMA_IMAGE="ollama/ollama:0.5.11" # Pinned to current stable version

echo "🚀 Starting Persistent Private Agent Runtime Installation..."

# ==========================================
# 1. k3s Check & Isolated Config Sync
# ==========================================
if ! command -v k3s &> /dev/null; then
    echo "❌ Error: k3s not found. Please install it once using: curl -sfL https://get.k3s.io | sh -"
    exit 1
fi

# Sync the config to our dedicated, isolated file
echo "🔑 Syncing isolated k3s access to $K3S_KUBECONFIG..."
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$K3S_KUBECONFIG"
sudo chown $(id -u):$(id -g) "$K3S_KUBECONFIG"
chmod 600 "$K3S_KUBECONFIG"

# Use standard kubectl (automatically points to $KUBECONFIG)
KUBECMD="kubectl"

# ==========================================
# 2. Namespaces & Storage
# ==========================================
echo "🛡️  Configuring Namespaces & Storage..."
$KUBECMD create namespace "$NAMESPACE_OLLAMA" --dry-run=client -o yaml | $KUBECMD apply -f -
$KUBECMD create namespace "$NAMESPACE_AGENTS" --dry-run=client -o yaml | $KUBECMD apply -f -

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

# ==========================================
# 3. Deploy Ollama (Pinned Version, High-Memory + Persistent)
# ==========================================
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
echo "✅ PERSISTENT SETUP COMPLETE"
echo "Model: $MODEL_NAME (32k Context Preset Ready)"
echo "Isolated Config: $K3S_KUBECONFIG"
echo "Memory Limit: 10Gi"
echo "=========================================="
