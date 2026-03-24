# 🛠️ Spec: Provisioning V2 Integration (Observability & Persistence)

## 🎯 Goal
Integrate "Mobile Dashboard V2" (btop + ollama ps) into all mobile node provisioning scripts and ensure that the Ollama service is persistent and accessible via its API across device reboots.

## 🏗️ Affected Components
1.  `private-agent-runtime/mobile-nodes/provision-rooted-node.sh`
2.  `private-agent-runtime/mobile-nodes/provision-unrooted-node.sh` (via `mobile-agent-setup.sh`)
3.  `private-agent-runtime/mobile-nodes/provision-lineage-node.sh`
4.  `private-agent-runtime/mobile-nodes/mobile-agent-setup.sh`

## 🛠️ Implementation Details

### 1. Dependency Updates
All provisioning scripts must ensure the following packages are installed in Termux:
- `btop` (replacing or supplementing `htop`)
- `tmux`
- `watch`
- `termux-boot` (if available via F-Droid)

### 2. Standardized `start-dashboard.sh`
The dashboard script should be unified across all provisioning methods where possible.
- **Pane 0 (Top, ~70%):** `btop`
- **Pane 1 (Bottom, ~30%):** `watch -n 2 "ollama ps"`

### 3. Persistence & API Accessibility (Reboot Resilience)
- **Boot Script:** All scripts must configure a `~/.termux/boot/` script that starts:
  - `sshd`
  - `termux-wake-lock`
  - `start-dashboard.sh` (which in turn starts Ollama)
- **Ollama Environment:** Ensure `OLLAMA_HOST=0.0.0.0` is set whenever `ollama serve` is called, allowing external API access from the k3s cluster.
- **Service Verification:** Add logic to `start-dashboard.sh` to verify `ollama` is running and the API is responsive before attaching the dashboard.

### 4. Rooted vs Unrooted Variations
- **Rooted/Lineage:** `ollama ps` and `ollama serve` must be executed within the Ubuntu chroot environment (e.g., via `su -g 3003 -c "chroot ..."`).
- **Unrooted:** Ollama runs directly in the Termux environment.

## 📋 Execution Plan

### Step 1: Update `mobile-agent-setup.sh` (Unrooted Path)
- Update `pkg install` to include `btop` and `watch`.
- Update the `start-dashboard.sh` block to include `OLLAMA_HOST=0.0.0.0` and persistence logic.
- Ensure `~/.termux/boot/start-agent` is correctly configured.

### Step 2: Update `provision-rooted-node.sh`
- Update the inline `start-dashboard.sh` generation.
- Ensure `OLLAMA_HOST=0.0.0.0` is used for the chrooted `ollama serve`.
- Verify `termux-boot` configuration is robust.

### Step 3: Update `provision-lineage-node.sh`
- Add `start-dashboard.sh` generation and `.bashrc` integration.
- Ensure `OLLAMA_HOST=0.0.0.0` is used for the chrooted `ollama serve`.
- Configure `~/.termux/boot/start-agent`.

### Step 4: Validation
- Verify on a test node that `btop` starts, `ollama ps` reflects model state, and the API is reachable from the host machine after a reboot.

## ✅ Success Criteria
- [ ] All 3 provisioning scripts successfully deploy the V2 dashboard.
- [ ] `btop` is the primary monitor.
- [ ] `ollama ps` provides real-time inference status.
- [ ] **Persistence:** Ollama API is available at `http://<phone-ip>:11434` immediately after a reboot.
