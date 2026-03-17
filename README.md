# Private Agent Runtime

This repository contains the infrastructure code for running a local AI cluster using Kubernetes. The goal is to provide a sandboxed environment for executing AI agents with access to a locally hosted LLM.

## Architecture

The setup script provisions the following environment:

- **Kubernetes Cluster**: A lightweight `k3d` cluster named `agent-sandbox`.
- **Namespaces**:
  - `ollama-system`: Dedicated namespace for the local LLM inference server.
  - `agent-execution`: A sandboxed namespace for running AI agents.
- **Security**: A default-deny egress network policy is applied to the `agent-execution` namespace to prevent agents from making unauthorized outbound connections.
- **LLM Server**: An Ollama deployment is configured in CPU mode within the `ollama-system` namespace. It is exposed via a LoadBalancer service mapping port `11434` directly to your host machine's `localhost:11434`.
- **Model**: Automatically pulls the `qwen2.5:0.5b` model (CPU-friendly) into the cluster.
- **CLI Tools**: Installs [Claude Code](https://claude.ai/code) locally and configures it to communicate with the local Ollama instance running inside the cluster.

## Prerequisites

The setup script checks for and requires the following dependencies on your host machine:
- `docker`
- `kubectl`
- `k3d`

## Quick Start

1. Clone this repository and navigate to the directory:
   ```bash
   cd private-agent-runtime
   ```

2. Run the setup script:
   ```bash
   ./setup.sh
   ```

3. Once complete, you can start Claude Code connected to your local cluster using the exported environment variables provided at the end of the script:
   ```bash
   export ANTHROPIC_BASE_URL="http://localhost:11434"
   export ANTHROPIC_AUTH_TOKEN="ollama"
   export ANTHROPIC_API_KEY=""
   claude --model qwen2.5:0.5b
   ```
