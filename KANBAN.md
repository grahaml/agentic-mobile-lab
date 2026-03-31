# 🗺️ Project Roadmap & Kanban

## 📋 Backlog
### 🧪 Testing & Validation
- [ ] [TEST-003] Re-test Motorola Edge node stability | #med
- [ ] [TEST-004] Re-test Mistral performance in k3s cluster | #high

### 📝 Documentation & Narrative
- [x] [DOC-001] Extract diagrams from articles and centralize in `diagrams/` folder | #low | Completed 2026-03-24
- [x] [DOC-002] Cleanup & align articles (k3s intro -> mobile realization -> hardware breakdown) | #med | Completed 2026-03-24

### 📱 Node & Hardware Setup
- [ ] [NODE-001] Provision Samsung S20 FE node | #high
- [ ] [NODE-002] Procure physical lab hardware setup | #med
- [ ] [APP-001] Setup Matrix on Essential PH-1 | #low
  - [x] [APP-001-A] Draft Matrix PH-1 Spec | [Spec](specs/matrix-ph1-spec.md)
  - [x] [APP-001-B] Draft Matrix Overview Doc | [Doc](docs/matrix-overview.md)
  - [x] [APP-001-C] Environment Prep & Dependency Install | Completed 2026-03-23
  - [ ] [APP-001-D] Install & Configure Conduit (ARM64)
  - [ ] [APP-001-E] Implement Boot Persistence (`termux-boot`)
  - [ ] [APP-001-F] Setup Observability (Superceded by [NODE-003])
  - [x] [APP-001-G] Validate Ollama (1.5B) in Ubuntu Chroot | Completed 2026-03-23

### 🤖 Agentic Infrastructure
- [ ] [APP-002] Finalize agentic harness (Aider vs. Claude Code vs. Custom Bash) | #critical
- [ ] [NODE-004] Provision Samsung S8 (The Architect) as unrooted node | #high

### 🕸️ Nested MCP Architecture (The "Hub-and-Spoke") | [Spec](specs/nested-mcp-architecture.md)
- [x] [MCP-MVW-001] Phase 1: Minimal Viable Workflow (MVW) | #critical | Completed 2026-03-26
  - [x] Implement `run_mvw_security_scan` on Gateway FastMCP
  - [x] Configure `sec_reviewer` role in Orchestrator for Mobile Node routing
  - [x] Implement `grep_vulnerabilities` tool on Internal FastMCP
  - [x] End-to-end validation with `Aider`/`OpenCode`
- [ ] [MCP-GW-001] Implement Gateway FastMCP (SSE) | #med
  - [ ] [MCP-GW-001-A] Expose high-level workflows as tools (e.g., `run_security_review`)
  - [ ] [MCP-GW-001-B] Configure SSE for remote access from Local Machine
- [ ] [MCP-ORCH-001] Develop FastAPI Orchestrator (The Brain) | #med
  - [ ] [MCP-ORCH-001-A] Implement Router-Broker logic with tool-call interception
  - [ ] [MCP-ORCH-001-B] State management for distributed workflows
  - [ ] [MCP-ORCH-001-C] Role-based tool schema injection per node
- [ ] [MCP-INT-001] Implement Internal FastMCP (Raw Tools) | #med
  - [ ] [MCP-INT-001-A] Expose system tools (`read_db`, `grep_logs`, `execute_bash`)
  - [ ] [MCP-INT-001-B] Enforce IP-based whitelist (Allow only Orchestrator)
- [ ] [SWARM-001] Optimize Peripheral Swarm for Stateless Inference | #low
  - [ ] [SWARM-001-A] Standardize Ollama API endpoints across mobile nodes
  - [ ] [SWARM-001-B] Verify tool-calling capability on mobile Ollama instances

## 🏗️ In Progress
- [ ] [APP-001] Setup Matrix on Essential PH-1 | #low
  - [x] [APP-001-A] Draft Matrix PH-1 Spec | [Spec](specs/matrix-ph1-spec.md)
  - [x] [APP-001-B] Draft Matrix Overview Doc | [Doc](docs/matrix-overview.md)
  - [x] [APP-001-C] Environment Prep & Dependency Install | Completed 2026-03-23
  - [ ] [APP-001-D] Install & Configure Conduit (ARM64)
  - [ ] [APP-001-E] Implement Boot Persistence (`termux-boot`)
  - [ ] [APP-001-F] Setup Observability (Superceded by [NODE-003])
  - [x] [APP-001-G] Validate Ollama (1.5B) in Ubuntu Chroot | Completed 2026-03-23
- [/] [NODE-003] Implement Observability V2 (gotop + ollama ps) across fleet | #high
  - [x] [NODE-003-A] Draft Provisioning V2 Spec | [Spec](specs/provisioning-v2-integration.md)
  - [x] [NODE-003-B] Update `mobile-agent-setup.sh` (Unrooted)
  - [x] [NODE-003-C] Update `provision-rooted-node.sh`
  - [x] [NODE-003-D] Update `provision-lineage-node.sh`
  - [x] [NODE-003-E] Deploy Dashboard V2 to Samsung S10e
  - [x] [NODE-003-F] Deploy Dashboard V2 to Motorola Edge (Chroot-aware)
- [ ] [APP-003] Develop platform capability for dynamic device metadata resolution (SSH user, IP, Port) | #high (Base whitelist implemented in test-mobile-node-via-ssh.py)

  - [x] [MIG-009-D] Restore workloads and verify networking (NetPols)
- [x] [MIG-008] Upgrade Macbuntu Host to Ubuntu 24.04 LTS | #critical | Completed 2026-03-24
- [x] [APP-004] Create Dynamic Agent Executor (`swarm-agent.py`) | #critical | Completed 2026-03-22
  - [x] [APP-004-A] Draft `swarm-agent.py` Spec | [Spec](specs/dynamic-agent-executor.md)
  - [x] [APP-004-B] Implement dynamic Secret mounting logic (RBAC-based) | [RBAC Manifest](manifests/agent-executor-rbac.yaml)
  - [x] [APP-004-C] Implement automated Pod lifecycle (Create -> Exec -> Cleanup)
- [x] [TEST-002] Re-test Samsung S10e node stability | #med | Completed 2026-03-22
- [x] [TEST-001] Build comprehensive, documented test runner (align with "Private Agent Runtime" article) | #high | Completed 2026-03-22
- [x] [MIG-006] Re-pull AI models (mistral) | #low | Completed 2026-03-22
- [x] [MIG-007] Refactor `setup.sh` | #med | Completed 2026-03-22
- [x] [MIG-005] Restore workloads to k3s | #med | Completed 2026-03-22
- [x] [MIG-001] Backup current state (k3d) | #critical | Completed 2026-03-22
- [x] [MIG-002] Teardown k3d cluster | #critical | Completed 2026-03-22
- [x] [MIG-003] Install Native k3s | #critical | Completed 2026-03-22
- [x] [MIG-004] Configure Kubeconfig | #critical | Completed 2026-03-22
- [x] [K3S-000] Initial Cluster Research & Compatibility Check | #low | Completed 2024-03-21

---

## 🗒️ Task Details & Granular Notes

### [APP-001] Essential PH-1 (The Zombie) Setup
- **Ghost Touch Mitigation:** Successfully suppressed `hbtp_input` (event7) via `disable_touch.sh`.
- **Ubuntu Chroot:** Verified and mounted.
- **Ollama Inference:** `qwen2.5-coder:1.5b` validated (~1.9s eval duration).

### [DOC-002] Article Narrative Alignment
1. **Article 1**: Playing around with k3s (The Foundation).
2. **Article 2**: "Holy shit, I can do this with phones" (The Realization).
3. **Article 3**: Breakdown of all phones setup (The Fleet).

### [APP-002] Agentic Harness Decision
- **Aider**: Great for interactive editing.
- **Claude Code**: High quality, but requires external connectivity?
- **Custom Bash**: Maximum control, low overhead.
