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
SERVICE_NAME="mobile-scout"

# 1. Validation
if [ -z "$1" ]; then
    echo "❌ Usage: ./bridge-phone.sh <PHONE_IP>"
    echo "Example: ./bridge-phone.sh 192.168.4.50"
    exit 1
fi

PHONE_IP=$1

echo "🔗 Bridging Mobile Agent at $PHONE_IP to cluster..."

# 2. Create the Kubernetes manifest
cat <<EOF > mobile-bridge.yaml
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_NAME
  namespace: $NAMESPACE
  labels:
    agent-role: scout
    device-type: mobile
spec:
  ports:
    - name: ssh
      port: 8022
      targetPort: 8022
    - name: ollama
      port: 11434
      targetPort: 11434
  # Removed ClusterIP: None
---
apiVersion: v1
kind: Endpoints
metadata:
  name: $SERVICE_NAME
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
# Idempotently create the secret if it doesn't exist
SECRET_NAME="${SERVICE_NAME}-ssh-key"
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "🔑 Creating Kubernetes Secret for $SERVICE_NAME..."
    # We assume the key exists from the provisioner step
    kubectl create secret generic "$SECRET_NAME" \
        --from-file="id_mobile_$SERVICE_NAME=$HOME/.ssh/id_mobile_$SERVICE_NAME" \
        -n "$NAMESPACE"
fi

echo "🛰️  Applying Service and Endpoints for $SERVICE_NAME..."
kubectl apply -f mobile-bridge.yaml

echo "✅ Bridge Created!"
echo "------------------------------------------"
echo "DNS Address: $SERVICE_NAME.$NAMESPACE.svc.cluster.local"
echo "SSH Port: 8022"
echo "Ollama Port: 11434"
echo "------------------------------------------"
echo "Testing connectivity from Macbuntu..."
if ping -c 1 -W 2 "$PHONE_IP" > /dev/null; then
    echo "📶 Network: UP"
else
    echo "🚫 Network: UNREACHABLE (Check if phone is on the same Wi-Fi)"
fi
