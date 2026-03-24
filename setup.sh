#!/bin/bash

# ==========================================
# Modernized Private Agent Runtime Setup
# Focus: Security, Isolation, and Ubuntu 24.04 Compatibility
# ==========================================

set -euo pipefail # Strict error handling: exit on error, unset vars, and pipe failures

# --- Configuration ---
NAMESPACE_AGENTS="agent-execution"
NAMESPACE_OLLAMA="ollama-system"
MODEL_NAME="mistral" 

# Virtual Environments
PROJECT_VENV="$HOME/.venv-private-agent-runtime"
AIDER_VENV="$HOME/.venv-aider"

echo "🚀 Starting Modernized Private Agent Runtime Installation..."

# ==========================================
# 1. Dependency & Capability Checks
# ==========================================
echo "🔍 Checking system capabilities..."

# Ensure python3-venv is present (Crucial for modern Ubuntu)
if ! python3 -m venv --help > /dev/null 2>&1; then
    echo "❌ Error: python3-venv is not installed."
    echo "Please run: sudo apt update && sudo apt install python3-venv"
    exit 1
fi

# Check for k3s / kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl not found."
    exit 1
fi

# Ensure k3s is using nftables if available (standard for Ubuntu 24.04)
if iptables --version | grep -q "nf_tables"; then
    echo "✅ nftables backend detected (Modern Ubuntu default)."
fi

# ==========================================
# 2. Project Virtual Environment (Isolation)
# ==========================================
if [ ! -d "$PROJECT_VENV" ]; then
    echo "📦 Creating project virtual environment at $PROJECT_VENV..."
    python3 -m venv "$PROJECT_VENV"
fi

echo "📦 Updating project dependencies..."
"$PROJECT_VENV/bin/pip" install --quiet -U pip
if [ -f "requirements.txt" ]; then
    "$PROJECT_VENV/bin/pip" install --quiet -r requirements.txt
else
    # Fallback if requirements.txt isn't in current dir
    "$PROJECT_VENV/bin/pip" install --quiet kubernetes
fi

# ==========================================
# 3. Cluster Security Configuration
# ==========================================
echo "🛡️  Hardening Kubernetes Namespaces & Policies..."

# Create namespaces if they don't exist
kubectl create namespace "$NAMESPACE_OLLAMA" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$NAMESPACE_AGENTS" --dry-run=client -o yaml | kubectl apply -f -

# Apply Default-Deny Egress Policy to Agents
kubectl apply -f - <<EOF
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

echo "✅ Security policies applied."

# ==========================================
# 4. Deploy/Verify Ollama
# ==========================================
echo "🧠 Deploying CPU-Optimized Ollama..."

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
            cpu: "1"
            memory: "2Gi"
          limits:
            cpu: "2"
            memory: "4Gi"
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

echo "⏳ Waiting for Ollama (timeout 60s)..."
kubectl rollout status deployment/ollama -n "$NAMESPACE_OLLAMA" --timeout=60s || echo "⚠️ Rollout taking longer than expected..."

# ==========================================
# 🎉 Summary
# ==========================================
echo "=========================================="
echo "✅ MODERNIZATION COMPLETE"
echo "=========================================="
echo "Project Venv: $PROJECT_VENV"
echo ""
echo "To run project tools (e.g., swarm-agent.py):"
echo "  $PROJECT_VENV/bin/python3 swarm-agent.py --help"
echo "=========================================="
