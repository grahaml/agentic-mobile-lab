# Part 1: The Foundation (k3s & The Sandbox)

The rise of agentic AI—autonomous systems that can write and execute code—presents a dual challenge: how do we provide these agents with the power they need while ensuring they don't accidentally (or maliciously) compromise our host systems?

This article explores the architecture, hurdles, and outcomes of the **Private Agent Runtime**, a project dedicated to building a secure, locally-hosted Kubernetes cluster for AI agents, entirely built and optimized on a modern **Ubuntu 24.04 LTS** host environment.

## 1. The Vision: A Secure, Zero-Trust Laboratory

The goal was simple but ambitious: create a "black box" where an AI agent could live, think, and work. This environment needed to satisfy three requirements:
1.  **Data Sovereignty:** No code or prompts should ever leave the local network.
2.  **Execution Isolation:** Any code the agent generates must run in a transient sandbox, not on the developer's workstation.
3.  **Hardened Egress:** Even if an agent "hallucinates" a curl command to a malicious domain, the network layer must block it.

## 2. Architecture: The Multi-Layered Fortress

The runtime is built on a tiered architecture using **k3s** (a lightweight Kubernetes distribution) running natively on an Ubuntu 24.04 Linux host. Using modern Linux primitives like `cgroup v2` and `nftables`, the cluster guarantees strict isolation and high performance.

*(See `diagrams/k3s-architecture.mermaid` for the cluster topology)*

### Layer 1: The Orchestration Plane
We used Kubernetes namespaces to enforce strict logical separation:
*   **`ollama-system`**: The "Brain." This namespace houses the Ollama inference server, providing LLM capabilities to the rest of the cluster.
*   **`agent-execution`**: The "Hands." This is a heavily restricted sandbox where agents operate. It is protected by a `default-deny-egress` NetworkPolicy.

### Layer 2: Ephemeral Execution (`swarm-exec.py`)
To prevent "state drift" and ensure security, we developed a utility called `swarm-exec.py`. Instead of letting an agent run code in its own persistent container, the agent sends its Python code to this utility, which spins up a fresh pod, injects the code via Base64, executes it, streams the logs, and immediately destroys the pod.

*(See `diagrams/ephemeral-execution.mermaid` for the execution sequence)*

## 3. Hard-Won Lessons: Troubleshooting the Sandbox

Building this wasn't without its hurdles. Here are the key technical challenges we overcame:

### The NetworkPolicy Illusion
The most critical discovery was that standard clusters often skip network policy enforcement. During initial testing, we found that pods in the "sandboxed" namespace could still reach the public internet if not configured correctly. 

*(See `diagrams/network-policy.mermaid` for the CNI bypass fix)*

*   **The Fix:** By using a native `k3s` installation paired with Ubuntu 24's `nftables` backend, the integrated network policy controller is enabled by default, ensuring immediate enforcement of security boundaries.

### Verified Isolation (The Red Team Test)
To ensure the isolation worked, we developed `exfiltration-test.py`. This script attempts to reach common external IPs and DNS servers. Only after this script fails to "phone home" do we consider the runtime ready for agentic work.

### Model Selection: Speed vs. Stability
We found that while `qwen2.5:0.5b` is incredibly fast for small utility tasks, its limited context handling often leads to "repetition loops" when faced with complex system prompts. For reliable coding tasks, the **Mistral 7B** model (running in CPU-optimized mode) proved to be the "minimum viable stability" for the swarm.

## 4. The Turning Point

The project successfully delivered a reproducible, one-shot installation script (`setup.sh`) that transforms a standard Ubuntu 24.04 Linux box into a hardened AI laboratory.

We had the brain, and we had the sandbox. But while the primary cluster handled the heavy lifting, we realized we needed horizontal scaling to simulate real multi-agent team dynamics. 

Looking at a drawer full of old Android phones, a "holy shit" moment occurred: *Could we repurpose these forgotten devices as fully autonomous cluster nodes?*
