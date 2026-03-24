# 📱 Spec: Mobile Dashboard V2 (The "Observability" Update)

## 🎯 Goal
Replace the existing basic `tmux` + `htop` dashboard on mobile nodes with a high-fidelity observability suite that provides real-time feedback during LLM inference and system health monitoring, optimized for small screens.

## ⚡ Problems to Solve
1.  **Low-Signal Monitoring**: `htop` doesn't clearly show the "Thinking" state of the LLM in a way that is easily glanceable.
2.  **Noisy Logs**: Tailing `ollama.log` is often unreadable on small phone screens and fills the buffer with irrelevant detail.
3.  **Thermal Visibility**: High-performance LLM inference causes significant heat; visibility into thermal throttling is critical for long-term node health.

## 🛠️ Proposed Solution

### 1. The Monitoring Stack
*   **Primary Resource Monitor**: `btop`. It provides a superior visual representation of per-core CPU usage, memory pressure, and **system temperatures** (if available via sensors).
*   **Active Inference Monitor**: `watch -n 2 "ollama ps"`. This shows exactly which models are loaded and running, providing a clean "Thinking/Idle" status.

### 2. Improved Layout (Tmux)
*   **Pane 0 (Top)**: `btop` (approx. 70% height).
*   **Pane 1 (Bottom)**: `watch -n 2 "ollama ps"` (approx. 30% height).

### 3. Exclusions
*   **No Battery Monitoring**: Nodes are expected to be permanently powered.
*   **No Log Tailing**: Logs will be suppressed from the main dashboard to maintain high signal-to-noise ratio.

## 📋 Implementation Plan

### Phase 1: Dependency Update
- Ensure `btop` is installed in Termux (`pkg install btop -y`).
- Ensure `tmux` and `watch` are available.

### Phase 2: Script Refactor (`start-dashboard.sh`)
- Update the layout to use a two-pane vertical split.
- Replace `htop` with `btop`.
- Replace the log tailing command with the `ollama ps` watch command.

### Phase 3: Global Rollout
- Update `provision-rooted-node.sh` and `mobile-agent-setup.sh` to use the new dashboard configuration by default.

## 🚀 Success Criteria
- [ ] `btop` is running and responsive.
- [ ] `ollama ps` correctly shows "None" when idle and the model name when inference is active.
- [ ] Thermal sensors are visible in `btop` (where supported by the kernel).
