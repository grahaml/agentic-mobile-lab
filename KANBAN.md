# 🗺️ Project Roadmap & Kanban

## 📋 Backlog
### 🧪 Testing & Validation
- [ ] [TEST-003] Re-test Motorola Edge node stability | #med
- [ ] [TEST-004] Benchmark 7B inference on S20+ vs Macbuntu CPU | #high

### 📝 Documentation & Narrative
- [x] [DOC-001] Extract diagrams from articles and centralize in `diagrams/` folder | #low | Completed 2026-03-24
- [x] [DOC-002] Cleanup & align articles (k3s intro -> mobile realization -> hardware breakdown) | #med | Completed 2026-03-24

### 📱 Node & Hardware Setup
- [ ] [NODE-002] Procure physical lab hardware setup | #med
- [ ] [NODE-004] Provision Samsung S8 (The Architect) as unrooted node | #high

### 🤖 Agentic Infrastructure
- [x] [APP-002] Finalize agentic harness (Shift to Gemini CLI + Custom Skills) | #critical | Completed 2026-03-31

---

## 🚀 S20+ Tech Lead & Gemini Skill Integration (CURRENT FOCUS)
### [ARCH-001] S20+ Hardening & Optimization
- [x] [ARCH-001-A] Implement Samsung-specific de-bloat list in `provision-unrooted-node.sh` | #high | Completed 2026-03-31
- [x] [ARCH-001-B] Adjust memory limits on S20+ to prioritize Ollama | #med | Completed 2026-03-31
- [x] [ARCH-001-C] Pull `qwen2.5-coder:7b` & create `qwen-large-ctx` (12k) preset on S20+ | #high | Completed 2026-03-31

### [ARCH-002] Native MCP & Skill Development
- [x] [ARCH-002-A] Register Cluster Gateway as system MCP in `~/.gemini/settings.json` | #critical | Completed 2026-03-31
- [x] [ARCH-002-B] Build `agent-swarm-orchestrator` skill using `skill-creator` | #high | Completed 2026-03-31
- [x] [ARCH-002-C] Install `agent-swarm-orchestrator` skill globally | #med | Completed 2026-03-31

### [ARCH-003] Cluster Resource Recovery
- [x] [ARCH-003-A] Downscale local Ollama to `llama3.2:1b` for resource recovery | #low | Completed 2026-03-31
- [x] [ARCH-003-B] Update in-cluster `orchestrator.py` to route high-complexity tasks to S20+ | #med | Completed 2026-03-31

---

## 🏗️ In Progress
- [/] [NODE-003] Implement Observability V2 (gotop + ollama ps) across fleet | #high
  - [x] [NODE-003-A] Draft Provisioning V2 Spec | [Spec](specs/provisioning-v2-integration.md)
  - [x] [NODE-003-B] Update `mobile-agent-setup.sh` (Unrooted)
  - [x] [NODE-003-C] Update `provision-rooted-node.sh`
  - [x] [NODE-003-D] Update `provision-lineage-node.sh`
  - [ ] [NODE-003-E] Deploy Dashboard V2 to Samsung S10e
  - [/] [NODE-003-F] Deploy Dashboard V2 to Motorola Edge (Chroot-aware)
  - [x] [NODE-003-G] Relocate centralized fleet telemetry (receiver/collector/dashboard + push agent) into `telemetry/`, with `telemetry/fleet.yaml` as the canonical device pool | [Specs](specs/telemetry-dashboard.md)

---

## ✅ Completed
- [x] [MCP-MVW-001] Phase 1: Minimal Viable Workflow (MVW) | #critical | Completed 2026-03-26
- [x] [MIG-008] Upgrade Macbuntu Host to Ubuntu 24.04 LTS | #critical | Completed 2026-03-24
- [x] [APP-004] Create Dynamic Agent Executor (`swarm-agent.py`) | #critical | Completed 2026-03-22
- [x] [K3S-000] Initial Cluster Research & Compatibility Check | #low | Completed 2024-03-21
- [x] [MIG-001..007] Cluster Migration & setup.sh Refactor | Completed 2026-03-31
- [x] [RE-ARCH-2026] Transition to S20+ Tech Lead & Gemini Skills | Completed 2026-03-31

---

## 🗒️ Task Details & Granular Notes

### [ARCH-001] S20+ Tech Lead Transition
- **Status:** Provisioned via Wireless ADB. De-bloated and hardened.
- **Model:** Qwen 2.5 Coder 7B with 12k context window preset.

### [ARCH-002] Gemini Skills
- **Installed:** `agent-swarm-orchestrator` available globally.
- **Tools:** `mcp_agent_swarm_run_mvw_security_scan` registered and trusted.
