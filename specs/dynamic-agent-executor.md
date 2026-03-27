# Spec: Dynamic Agent Executor (`swarm-agent.py`)

## 🎯 Objective
Create a Python-based utility that automates the deployment of a transient "Agent Pod" within the `agent-execution` namespace. This pod must be dynamically configured with the correct SSH credentials to communicate with a specific mobile node.

## 🏗️ Architecture & Flow (Secure)
The `swarm-agent.py` script will act as a control plane for individual task execution, prioritizing secret isolation:

1.  **Device Resolution**: User specifies a device (e.g., `--device scout-sm-g970w`).
2.  **Pod Generation**: A Pod manifest is generated with:
    *   **ServiceAccount**: A specialized `agent-executor-sa` with restricted RBAC.
    *   **No Volume Mounts**: No static secret references in the manifest.
3.  **Secure Secret Retrieval**: 
    *   The Python code running *inside* the pod uses the Kubernetes API (`incluster_config`) to fetch the specific SSH secret into memory at runtime.
    *   The key is written only to a `tmpfs` location (e.g., `/dev/shm/id_rsa`) which resides in RAM, not on the node's physical disk.
4.  **Execution**: The SSH command uses the in-memory key, then explicitly wipes the `tmpfs` file upon completion.
5.  **Lifecycle Management**: 
    *   Stream logs/output to the host.
    *   Automatically delete the Pod upon completion.

## 🛠️ Configuration Details

### RBAC Security Model
To enable this, the following resources must be present in the `agent-execution` namespace:
*   **ServiceAccount**: `agent-executor-sa`
*   **Role**: `secret-reader` (allowed to `get` secrets).
*   **RoleBinding**: Binds the SA to the Role.

### In-Pod Retrieval Logic (Conceptual)
```python
from kubernetes import client, config
config.load_incluster_config()
v1 = client.CoreV1Api()
secret = v1.read_namespaced_secret(name="scout-sm-g970w-ssh-key", namespace="agent-execution")
key_data = secret.data["id_mobile_scout-sm-g970w"]
# Write to RAM-only storage
with open("/dev/shm/id_rsa", "wb") as f:
    f.write(base64.b64decode(key_data))
os.chmod("/dev/shm/id_rsa", 0o400)
```

### Pod Security Context
*   **Namespace**: `agent-execution` (strictly enforced).
*   **NetworkPolicy**: Inherits the `default-deny-egress` policy, allowing only internal cluster/mobile node traffic.

## 🚀 Usage Interface
```bash
# Example: Run a prompt test on the S10e
python3 swarm-agent.py --device scout-sm-g970w --prompt "Hello from the sandbox!"

# Example: Run a custom script on the Motorola
python3 swarm-agent.py --device scout-motorolaedge2023 --file tests/audit-node.py
```

## 🧪 Validation & Success Criteria
*   [ ] Pod is successfully created and enters `Running` state.
*   [ ] SSH key is readable inside the Pod at `/root/.ssh/id_rsa`.
*   [ ] SSH connection to the mobile node service (`{device}.svc.cluster.local`) succeeds.
*   [ ] Pod is deleted from the cluster immediately after execution.
