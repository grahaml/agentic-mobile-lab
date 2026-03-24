# Part 2: The Realization (Phones as Cluster Nodes)

*The modern developer's graveyard is littered with "failed" hardware: mid-range phones retired due to slow background updates, phones with shattered screens, and last-generation silicon. As local-first AI models mature, these devices represent an untapped reservoir of compute.*

At the end of building our k3s sandbox, we asked a radical question: could a drawer of old Android phones serve as dedicated AI worker nodes in a Kubernetes cluster?

The answer was a resounding yes. This article outlines the architectural breakthrough of transforming actual, retired Android devices into a sophisticated, decentralized "dev team" of autonomous agents.

## I. The Architectural Breakthrough

Instead of treating the phones as mere clients, we turned them into compute nodes using a **Rooted Chroot Pattern** (or native Termux for unrooted devices). Each phone runs a full Linux userland and hosts its own lightweight local LLM.

But how do you network an Android device securely into a strict Kubernetes namespace?

We bridged them into the cluster using Kubernetes `Service` and `Endpoint` objects mapped directly to the phones' LAN IP addresses.

*(See `diagrams/mobile-node-bridge.mermaid` for the bridge architecture)*

## II. The Toolbox: The Mobile Agent Stack

The entire stack is local-first, privacy-by-default, and designed to minimize latency on older processors.

| Tool | Category | Role |
| --- | --- | --- |
| **Termux** | Terminal Emulator | A full Linux userland on Android. This is the gateway layer where the `sshd` server runs, listening on port 8022. |
| **Ubuntu Chroot** | Execution Layer | A full Ubuntu 24.04 userland mounted on rooted devices. It provides a standard environment for our agents. |
| **Ollama** | LLM Engine | Native arm64 ports. Runs quantized GGUF models (like `qwen2.5-coder:1.5b`) directly on the device's CPU/RAM. |
| **Kubernetes Endpoints** | Cluster Bridge | Maps the physical phone IPs into the `agent-execution` namespace's internal DNS. |
| **Tmux / gotop** | Observability | Our "Dashboard V2", offering persistent sessions to monitor resource usage and active Ollama inferences on device. |

## III. Identity Without Accounts

To treat these devices as separate "employees," we had to establish clear boundaries and unique cryptographic identities. We didn't use standard user accounts or complex OIDC setups. Instead, we used a highly decentralized PKI presentation model.

**The Workflow:**
1.  **Key Generation:** Every phone gets its own unique, passphrase-less SSH key generated via a `provision-mobile-node.sh` script.
2.  **Secret Management:** These keys are registered in the k3s cluster as Kubernetes `Secrets` inside the `agent-execution` namespace.
3.  **Dynamic Execution:** A dynamic agent executor (`swarm-agent.py`) running in the cluster dynamically mounts the appropriate SSH secret based on the requested persona, and reaches out to the phone.

The host can seamlessly delegate tasks to a phone via SSH:
```bash
cat code_to_audit.py | ssh -p 8022 -i /secret/key agent@scout-motorolaedge2023 "sudo ~/enter_lab.sh audit"
```

## IV. The Edge of Reality

We had a perfectly sound theoretical architecture. We had our robust k3s host on Ubuntu 24.04. We had the SSH bridges mapped and our Endpoints defined. We had proven that identity and network policies held up under scrutiny.

But theory is one thing. When we actually opened the drawer and started plugging in the physical devices—dealing with manufacturer locks, aggressive OS memory killers, and failing hardware—we hit the chaotic reality of reclaimed silicon. The clean Kubernetes manifests were about to meet the messy trenches.
