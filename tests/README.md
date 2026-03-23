# 🧪 Mobile Node Verification Tests

This directory contains scripts to verify the functionality and security of the mobile agent nodes.

## 🚀 Secure SSH Test Runner (`test-mobile-node-via-ssh.py`)

This script tests model inference by connecting to a mobile node via SSH and executing the `enter-lab.sh audit` command.

### 🛡️ Security Features
- **Device Whitelisting:** Prevents SSRF by only allowing known service names.
- **Input Sanitization:** Uses `shlex.quote` to prevent remote shell injection.
- **No `shell=True`:** Uses `subprocess.run` with list arguments for secure execution.

### 📖 Usage

#### Running from within the Cluster (Recommended)
Since the script uses cluster-internal DNS (`.svc.cluster.local`), it is best run from a pod inside the `agent-execution` namespace.

```bash
# Example using a sandbox pod
python3 swarm-exec.py "python3 private-agent-runtime/tests/test-mobile-node-via-ssh.py --device scout-s10e --prompt 'Who are you?'"
```

#### Running Locally (via Bridge or VPN)
If you have a direct connection to the mobile node's IP, you can override the metadata:

```bash
# Example using manual overrides for a local bridge
python3 tests/test-mobile-node-via-ssh.py \
  --device scout-s10e \
  --user u0_a293 \
  --port 8022 \
  --prompt "Hello!"
```

### 📋 Available Devices
- `scout-s10e`
- `scout-motorolaedge2023`

---

## 🛠️ Other Tests (Legacy)
- `../test-mobile-bridge.py`: Tests Ollama HTTP API (v1).
- `../test-mobile-bridge-v2.py`: Tests Ollama HTTP API (v2) with port scanning.
- `../exfiltration-test.py`: Verifies network egress policies.
