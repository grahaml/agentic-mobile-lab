#!/bin/bash

# ==========================================
# 🛑 Cluster Decommission Script
# ==========================================
# This script wipes the k3s cluster to free up 
# resources for other projects.
# ==========================================

set -euo pipefail

echo "⚠️  WARNING: This will UNINSTALL k3s and DELETE all cluster data."
echo "Are you sure? (y/N)"
read -r response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Operation cancelled."
    exit 1
fi

if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    echo "🗑️  Running k3s-uninstall.sh..."
    sudo /usr/local/bin/k3s-uninstall.sh
else
    echo "❌ Error: /usr/local/bin/k3s-uninstall.sh not found."
    exit 1
fi

echo "🧹 Cleaning up local kubeconfig..."
rm -f "$HOME/.kube/k3s-config"

echo "=========================================="
echo "✅ DECOMMISSION COMPLETE"
echo "Resources have been freed."
echo "Use 'scripts/restore-cluster.sh' to bring it back."
echo "=========================================="
