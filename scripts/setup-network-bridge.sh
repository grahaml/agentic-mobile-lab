#!/bin/bash

# ==============================================================================
# Setup Isolated Lab Network & Tailscale Bridge
# ==============================================================================
# This script persists the networking configuration for the cascaded router 
# setup (TP-Link Sandbox) and the Tailscale Subnet Router bridge.
# ==============================================================================

set -e

# --- Configuration ---
LAB_INTERFACE="enx00e04c00408e"
LAB_SUBNET="10.0.0.0/24"
HOUSE_SUBNET="192.168.4.0/24"

echo "🛡️  Configuring Linux Kernel Forwarding..."
# Enable IPv4 Forwarding (Runtime)
sudo sysctl -w net.ipv4.ip_forward=1

# Persist Forwarding across reboots
if [ ! -f /etc/sysctl.d/99-tailscale-bridge.conf ]; then
    echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-tailscale-bridge.conf
    echo "net.ipv6.conf.all.forwarding = 1" | sudo tee -a /etc/sysctl.d/99-tailscale-bridge.conf
    echo "✅ Kernel forwarding persisted in /etc/sysctl.d/99-tailscale-bridge.conf"
fi

echo "🌉 Setting up IPtables Bridge (Tailscale <-> Lab)..."

# 1. Allow forwarding from Tailscale to the Lab Ethernet
sudo iptables -I FORWARD -i tailscale0 -o "$LAB_INTERFACE" -j ACCEPT

# 2. Allow established traffic back from the Lab to Tailscale
sudo iptables -I FORWARD -i "$LAB_INTERFACE" -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# 3. Masquerade traffic leaving for the Lab (so nodes can reply without static routes)
sudo iptables -t nat -I POSTROUTING -o "$LAB_INTERFACE" -j MASQUERADE

echo "🚧 Enforcing Sandbox Isolation (Blocking House access from Lab)..."
# This is a local fallback in case the Router's 'Dead Route' fails.
# It prevents Macbuntu from routing Lab traffic into the House network.
sudo iptables -I FORWARD -i "$LAB_INTERFACE" -d "$HOUSE_SUBNET" -j REJECT

echo "✅ Networking setup complete!"
echo "----------------------------------------------------------------"
echo "Interface: $LAB_INTERFACE"
echo "Lab Subnet: $LAB_SUBNET"
echo "House Subnet: $HOUSE_SUBNET"
echo "Tailscale Status: $(tailscale status --short)"
echo "----------------------------------------------------------------"
echo "💡 Reminder: Approve the 10.0.0.0/24 route in the Tailscale Admin Console."
