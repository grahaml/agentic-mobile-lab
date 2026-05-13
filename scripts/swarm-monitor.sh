#!/bin/bash

# --- Configuration ---
K3S_CONFIG="$HOME/.kube/k3s-config"
S20_IP="192.168.4.63"
S20_USER="u0_a319"
S20_KEY="$HOME/.ssh/id_mobile_architect-sm-g986w"

SESSION="swarm-monitor"

# Ensure we use the isolated config
export KUBECONFIG="$K3S_CONFIG"

# Start Tmux Session
tmux new-session -d -s $SESSION

# Pane 1: k9s (Cluster View)
tmux send-keys -t $SESSION:0.0 "k9s --namespace agent-execution" C-m

# Split horizontally for logs and phone status
tmux split-window -v -t $SESSION:0.0

# Pane 2: Orchestrator Logs
tmux send-keys -t $SESSION:0.1 "kubectl logs -f -n agent-execution -l app=agent-orchestrator --tail=20" C-m

# Split bottom pane vertically
tmux split-window -h -t $SESSION:0.1

# Pane 3: S20+ Remote Dashboard (SSH)
tmux send-keys -t $SESSION:0.2 "ssh -i $S20_KEY -p 8022 $S20_USER@$S20_IP" C-m

# Arrange panes
tmux select-pane -t $SESSION:0.0
tmux attach-session -t $SESSION
