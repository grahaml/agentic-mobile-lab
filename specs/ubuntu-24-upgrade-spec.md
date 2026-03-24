# Spec: Modernize Private Agent Runtime (Ubuntu 24.04 Compatibility & Hardening)

## 🎯 Goal
Ensure the Private Agent Runtime stack is fully compatible with modern Ubuntu environments (specifically Ubuntu 24.04 LTS), while enforcing strict security defaults and total isolation via virtual environments.

## 🏗️ Architecture Overview
- **Host OS:** Modern Ubuntu (Tested on 24.04 LTS).
- **Orchestration:** Native k3s (systemd).
- **Security:**
    - `Namespace` isolation for all components.
    - `NetworkPolicy` (default-deny-egress) for agent execution.
    - Standardized `cgroup v2` and `nftables` compatibility.
- **Isolation:** Mandatory `virtualenv` for all Python-based orchestration and tools.

## 📋 Task Breakdown

### 1. Modernized Dependency Management
- [x] Initialize and maintain a project-wide virtualenv: `~/.venv-private-agent-runtime`.
- [x] Update `requirements.txt` with pinned, secure versions of `kubernetes` and other dependencies.
- [x] Ensure `python3-venv` is used for all automation to avoid "externally managed environment" errors on modern Ubuntu.

### 2. `setup.sh` Modernization
- [x] Refactor `setup.sh` to be idempotent and OS-agnostic (focus on capability, not version).
- [x] Implement `set -u` and `set -o pipefail` for better error handling.
- [x] Update k3s installation logic to ensure compatibility with `iptables-nft`.
- [x] Automate the creation and update of the project virtualenv.
- [ ] Ensure `Aider` is installed in its own isolated venv to prevent dependency conflicts. (DEFERRED: Stalled during install, needs separate handling)

### 3. k3s Security & Compatibility Audit
- [x] Verify `cgroup v2` compatibility (default in Ubuntu 24.04).
- [x] Validate `agent-execution` namespace security (NetworkPolicies).
- [x] Ensure k3s is using the correct `iptables` backend.

### 4. Workload Validation
- [x] Re-verify Ollama deployment with proper resource constraints.
- [x] Test `swarm-agent.py` and `swarm-exec.py` within the project virtualenv.

### 5. Mobile Bridge & SSH Hardening
- [ ] Update SSH connection logic to support modern OpenSSH defaults in Ubuntu 24.04.
- [ ] Ensure SSH keys are handled securely via environment variables or k8s secrets, never logged.

## 🧪 Verification Plan
1. **Compatibility Test:** `bash setup.sh` runs successfully on Ubuntu 24.04.
2. **Isolation Test:** All python scripts run within the designated virtualenv; no global packages required.
3. **Security Test:** Egress blocking verified in `agent-execution` namespace.
4. **End-to-End:** Successful model inference and agent execution.
