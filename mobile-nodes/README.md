# 📱 Mobile Agent Nodes (The "Graveyard" Fleet)

This directory contains the automation and infrastructure for transforming old, rooted Android hardware into high-performance, autonomous "Security Analyst" and "Architect" nodes. These nodes operate within a **hardened Ubuntu chroot** and are bridged into your main `k3d` cluster on Macbuntu.

## 🏗️ Architecture: The "Rooted Chroot" Pattern

To maximize performance on older hardware while maintaining security, this setup uses a tiered architecture:

1.  **Host (Android/Termux)**: The "Gateway" layer. Runs `sshd` on port 8022.
2.  **Sandbox (Ubuntu Chroot)**: The "Execution" layer. A full Ubuntu userland where the `agent-lab` user lives.
3.  **Dispatcher (`enter_lab.sh`)**: The "Safe Front Door." A hardened script that validates incoming SSH commands and "dives" into the Ubuntu sandbox.
4.  **Cluster Bridge**: The phone is mapped into the `agent-sandbox` Kubernetes cluster as a `Service` and `Endpoint`, with its unique SSH key stored as a `Secret`.

## 🛠️ Onboarding a New Node (One-Shot Provisioning)

### 1. Prerequisites
*   **Rooted Device**: Use Magisk (Android 10+ recommended).
*   **Ubuntu installed in Termux**: A native chroot environment at `/data/local/ubuntu`.
*   **ADB Access**: The device must be connected to your Macbuntu host via USB or wireless ADB.

### 2. Run the Provisioner
From the `mobile-nodes` directory on your Macbuntu host, run:
```bash
./provision-mobile-node.sh
```
**What the provisioner automates:**
- Detects the phone's LAN IP and Termux user ID.
- Installs `openssh` in Termux and `ollama`/`llm` in the Ubuntu chroot.
- Generates a **device-specific, passphrase-less SSH key** for automated handoffs.
- Syncs the key and the `enter_lab.sh` dispatcher to the phone.
- Registers the phone in the Kubernetes cluster and creates a `Secret` for its key.

## 🛰️ Core Scripts

| Script | Location | Purpose |
| :--- | :--- | :--- |
| `provision-mobile-node.sh` | Macbuntu | One-shot setup for new rooted devices. |
| `bridge-phone.sh` | Macbuntu | Registers a phone IP into the K8s cluster DNS. |
| `enter-lab.sh` | Phone (`~/`) | Hardened dispatcher for incoming SSH tasks. |
| `auditor-test-pod.yaml` | Macbuntu | Example manifest for a cluster-to-phone audit. |

## 🚀 Usage: Triggering an Audit

### From Macbuntu Host:
```bash
cat my_code.py | ssh -p 8022 u0_a386@<PHONE_IP> "sudo ~/enter_lab.sh audit"
```

### From within the Kubernetes Cluster:
Deploy a pod that mounts the `mobile-scout-ssh-key` secret and uses `hostNetwork: true` to reach the phone's LAN IP. See `auditor-test-pod.yaml` for a complete example.

## 🛡️ Security Features
*   **Command Allow-listing**: `enter_lab.sh` only allows specific actions (`audit`, `status`, `update`) to prevent command injection.
*   **Isolated Identity**: Every phone gets its own unique SSH key, allowing you to revoke access to individual "Graveyard" nodes without affecting the fleet.
*   **User Sandboxing**: The agent runs as the non-root `agent-lab` user inside the Ubuntu chroot.
