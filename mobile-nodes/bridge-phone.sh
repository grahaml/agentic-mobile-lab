#!/bin/bash

# ==========================================
# 🛰️ Mobile Agent Bridge (Approach 1)
# ==========================================
# Registers a physical mobile device as a 
# "Virtual Pod" inside the k3d cluster.
# ==========================================

set -e

# Configuration
NAMESPACE="agent-execution"
# The 'Shortname' or Role (e.g., s20, moto, scout)
SVC_NAME=${2:-"scout"}
DEVICE_ID=${3:-"unknown"}
# Use the shortname for the K8s service to match the SSH config
PERSONA_NAME="$SVC_NAME"
MANIFEST_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/local-manifests"
MANIFEST_PATH="$MANIFEST_DIR/mobile-bridge-$PERSONA_NAME.yaml"

# 1. Validation
if [ -z "$1" ]; then
    echo "❌ Usage: ./bridge-phone.sh <PHONE_IP> [SVC_NAME] [DEVICE_ID]"
    echo "Example: ./bridge-phone.sh 10.0.0.20 s20 sm-g986w"
    exit 1
fi

PHONE_IP=$1

echo "🔗 Bridging Mobile Agent ($PERSONA_NAME) at $PHONE_IP to cluster..."

# 2. Create the Kubernetes manifest
mkdir -p "$MANIFEST_DIR"
cat <<EOF > "$MANIFEST_PATH"
apiVersion: v1
kind: Service
metadata:
  name: $PERSONA_NAME
  namespace: $NAMESPACE
  labels:
    agent-role: $SVC_NAME
    device-id: $DEVICE_ID
    device-type: mobile
spec:
  ports:
    - name: ssh
      port: 8022
      targetPort: 8022
    - name: ollama
      port: 11434
      targetPort: 11434
---
apiVersion: v1
kind: Endpoints
metadata:
  name: $PERSONA_NAME
  namespace: $NAMESPACE
subsets:
  - addresses:
      - ip: $PHONE_IP
    ports:
      - name: ssh
        port: 8022
      - name: ollama
        port: 11434
EOF

# 3. Apply to Cluster
SECRET_NAME="${PERSONA_NAME}-ssh-key"
# Fix: Force KUBECONFIG for k3s
export KUBECONFIG="$HOME/.kube/k3s-config"

if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "🔑 Creating Kubernetes Secret for $PERSONA_NAME..."
    kubectl create secret generic "$SECRET_NAME" \
        --from-file="id_mobile_$PERSONA_NAME=$HOME/.ssh/id_mobile_$PERSONA_NAME" \
        -n "$NAMESPACE"
fi

echo "🛰️  Applying Service and Endpoints for $PERSONA_NAME..."
kubectl apply -f "$MANIFEST_PATH"

echo "✅ Bridge Created!"
echo "------------------------------------------"
echo "DNS Address: $PERSONA_NAME.$NAMESPACE.svc.cluster.local"
echo "Labels: agent-role=$SERVICE_ROLE, device-id=$DEVICE_ID"
echo "SSH Port: 8022"
echo "Ollama Port: 11434"
echo "------------------------------------------"
echo "Testing connectivity from Macbuntu..."
if ping -c 1 -W 2 "$PHONE_IP" > /dev/null; then
    echo "📶 Network: UP"
else
    echo "🚫 Network: UNREACHABLE (Check if phone is on the same Wi-Fi)"
fi
