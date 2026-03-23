# 🗺️ Project Roadmap & Kanban

## 📋 Backlog
### 🧪 Testing & Validation
- [ ] [TEST-001] Build comprehensive, documented test runner (align with "Private Agent Runtime" article) | #high
- [x] [TEST-002] Re-test Samsung S10e node stability | #med | Completed 2026-03-22
- [ ] [TEST-003] Re-test Motorola Edge node stability | #med
- [ ] [TEST-004] Re-test Mistral performance in k3s cluster | #high

### 📝 Documentation & Narrative
- [ ] [DOC-001] Extract diagrams from articles and centralize in `diagrams/` folder | #low
- [ ] [DOC-002] Cleanup & align articles (k3s intro -> mobile realization -> hardware breakdown) | #med

### 📱 Node & Hardware Setup
- [ ] [NODE-001] Provision Samsung S20 FE node | #high
- [ ] [NODE-002] Procure physical lab hardware setup | #med
- [ ] [APP-001] Setup Matrix on Essential PH-1 | #low
  - [x] [APP-001-A] Draft Matrix PH-1 Spec | [Spec](specs/matrix-ph1-spec.md)
  - [x] [APP-001-B] Draft Matrix Overview Doc | [Doc](docs/matrix-overview.md)
  - [ ] [APP-001-C] Environment Prep & Dependency Install
  - [ ] [APP-001-D] Install & Configure Conduit (ARM64)
  - [ ] [APP-001-E] Implement Boot Persistence (`termux-boot`)
  - [ ] [APP-001-F] Setup Observability (Termux Dashboard/btop)

### 🤖 Agentic Infrastructure
- [ ] [APP-003] Develop platform capability for dynamic device metadata resolution (SSH user, IP, Port) | #high
- [ ] [APP-002] Finalize agentic harness (Aider vs. Claude Code vs. Custom Bash) | #critical

## 🏗️ In Progress
- [ ] [APP-003] Develop platform capability for dynamic device metadata resolution (SSH user, IP, Port) | #high (Base whitelist implemented in test-mobile-node-via-ssh.py)

## ✅ Done
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

### [DOC-002] Article Narrative Alignment
1. **Article 1**: Playing around with k3s (The Foundation).
2. **Article 2**: "Holy shit, I can do this with phones" (The Realization).
3. **Article 3**: Breakdown of all phones setup (The Fleet).

### [APP-002] Agentic Harness Decision
- **Aider**: Great for interactive editing.
- **Claude Code**: High quality, but requires external connectivity?
- **Custom Bash**: Maximum control, low overhead.
