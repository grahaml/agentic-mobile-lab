# 🏗️ Nested MCP Architecture (The "Hub-and-Spoke")

## 🗺️ Overview
This specification defines a three-tier "Nested MCP" architecture designed to provide secure, distributed, and resource-efficient agentic workflows across a k3s cluster and its peripheral mobile node swarm.

## 🎯 Phase 1: Minimal Viable Workflow (MVW)
To vet the architecture before scaling, implementation will first focus on a single, end-to-end "Security Audit" tool. This will exercise every layer of the Hub-and-Spoke model.

### MVW Tool Chain:
1.  **Gateway Tool:** `run_mvw_security_scan(code_snippet)`
2.  **Orchestrator Role:** `sec_reviewer` (Routed to a specific mobile node IP).
3.  **Internal Tool:** `grep_vulnerabilities(pattern)` (A simple mock/real tool on the Internal MCP).

### Success Criteria for Phase 1:
- [ ] `Aider`/`OpenCode` on Local Machine connects to Gateway MCP via SSE.
- [ ] Orchestrator intercepts a `tool_call` from a Mobile Node.
- [ ] Internal MCP executes a system-level command and returns data to the Orchestrator.
- [ ] Final verdict is returned to the Local Machine without the local machine ever having direct SSH/DB access.

## 🏗️ The Three-Tier Model

### Tier 1: Local Client (The Interface)
*   **Target Applications:** `Aider`, `Claude Code`, or `OpenCode`.
*   **Inference:** Points its LLM configuration to the main cluster Ollama endpoint (e.g., Macbuntu host).
*   **Tools:** Connects via SSE to the **Gateway FastMCP** server on the cluster.

### Tier 2: k3s Cluster (The Gateway & Orchestrator)
*   **Gateway FastMCP:**
    *   Exposes high-level **Workflows** as tools (e.g., `run_security_review(code)`).
    *   Does *not* expose raw infrastructure tools to the local client.
    *   Provides a secure boundary for the cluster.
*   **FastAPI Orchestrator (The "Brain"):**
    *   Receives workflow triggers from the Gateway.
    *   Manages the state machine for the distributed workflow.
    *   Routes token-crunching tasks to peripheral mobile nodes via `/api/chat`.
    *   Intercepts tool calls from mobile nodes and routes them to the **Internal FastMCP**.
*   **Internal FastMCP:**
    *   Exposes raw, powerful system tools (`read_db`, `grep_logs`, `execute_bash`, etc.).
    *   Restricted to internal cluster traffic (IP-whitelisted for the Orchestrator).

### Tier 3: Peripheral Swarm (The Worker Nodes)
*   **Hardware:** Repurposed mobile devices (Samsung S8, S10e, Motorola Edge, etc.).
*   **Software:** Bare-metal Ollama binary.
*   **Behavior:**
    *   **Stateless:** No local Python, no persistent state.
    *   **Tool-Aware:** Receives authorized tool schemas in the API payload from the Orchestrator.
    *   **Lean:** RAM/Compute is reserved exclusively for inference.

## 🔒 Security & Safety
1.  **Blast Radius Reduction:** If the local client is compromised, it only has access to high-level workflows, not the cluster filesystem or database.
2.  **Role-Based Sandboxing:** Mobile nodes only receive the tool schemas required for their specific role in a workflow.
3.  **The "Airgap":** Tool execution happens centrally on the orchestrator node, preventing mobile nodes from executing code directly on the infrastructure.

## 🚀 Workflow Execution Flow
1.  **Trigger:** `Aider` calls `run_cluster_security_review(code)` via Gateway MCP.
2.  **Initiate:** Gateway triggers the Orchestrator.
3.  **Node A (Coder):** Orchestrator sends a prompt to Node A (Mobile) to analyze the code.
4.  **Tool Call:** Node A decides it needs to scan logs and returns a `tool_call` for `grep_logs`.
5.  **Broker:** Orchestrator intercepts the `tool_call` and executes it via the **Internal FastMCP**.
6.  **Resolve:** Orchestrator sends the tool result back to Node A.
7.  **Complete:** Node A provides the final verdict, which the Orchestrator returns to the Gateway, and then to `Aider`.

## 🛠️ Implementation Tasks (See KANBAN.md)
*   [MCP-GW-001] Implement Gateway FastMCP (SSE)
*   [MCP-ORCH-001] Develop FastAPI Orchestrator
*   [MCP-INT-001] Implement Internal FastMCP
*   [SWARM-001] Optimize Peripheral Swarm
