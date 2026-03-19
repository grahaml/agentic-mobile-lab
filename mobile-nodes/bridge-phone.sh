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
SERVICE_ROLE=${2:-"scout"}
DEVICE_ID=${3:-"unknown"}
PERSONA_NAME="${SERVICE_ROLE}-${DEVICE_ID}"

# 1. Validation
if [ -z "$1" ]; then
    echo "❌ Usage: ./bridge-phone.sh <PHONE_IP> [SERVICE_ROLE] [DEVICE_ID]"
    echo "Example: ./bridge-phone.sh 192.168.4.50 matrix-host ph-1"
    exit 1
fi

PHONE_IP=$1

echo "🔗 Bridging Mobile Agent ($PERSONA_NAME) at $PHONE_IP to cluster..."

# 2. Create the Kubernetes manifest
cat <<EOF > mobile-bridge.yaml
apiVersion: v1
kind: Service
metadata:
  name: $PERSONA_NAME
  namespace: $NAMESPACE
  labels:
    agent-role: $SERVICE_ROLE
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
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "🔑 Creating Kubernetes Secret for $PERSONA_NAME..."
    kubectl create secret generic "$SECRET_NAME" \
        --from-file="id_mobile_$PERSONA_NAME=$HOME/.ssh/id_mobile_$PERSONA_NAME" \
        -n "$NAMESPACE"
fi

echo "🛰️  Applying Service and Endpoints for $PERSONA_NAME..."
kubectl apply -f mobile-bridge.yaml

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
