#!/bin/bash

# ==========================================
# 🛡️ Guardian Provisioner: Nexus 7 Hub
# ==========================================
# Sets up the Nexus 7 as a dedicated 
# Observability & Matrix TUI Hub.
# ==========================================

set -e

echo "🛡️ Starting Guardian Provisioning..."

# 1. Core Dependencies
echo "📦 Installing Termux dependencies..."
pkg update -y
pkg install -y tmux openssh git golang termux-api btop ncurses-utils

# 2. Install gomuks (Matrix TUI)
if ! command -v gomuks &> /dev/null; then
    echo "🏗️  Installing gomuks (Matrix TUI)..."
    go install github.com/tulir/gomuks@latest
    # Add to path if not there
    export PATH=$PATH:$(go env GOPATH)/bin
fi

# 3. Setup Guardian Dashboard Scripts
echo "📝 Creating start-guardian.sh..."
cat <<'EOF' > ~/start-guardian.sh
#!/bin/bash

# Ensure gomuks is in path
export PATH=$PATH:$(go env GOPATH)/bin

SESSION="guardian"

# Start tmux session
tmux new-session -d -s $SESSION

# Pane 1 (Left/Main): Matrix Client
tmux rename-window -t $SESSION:0 'WarRoom'
tmux send-keys -t $SESSION:0 'gomuks' C-m

# Pane 2 (Top Right): Node Health
tmux split-window -h -t $SESSION:0 -p 35
tmux send-keys -t $SESSION:0.1 'watch -n 10 "ssh -p 8022 graham-macbuntu \"./monitor-battery.sh\""' C-m

# Pane 3 (Bottom Right): K8s Events
tmux split-window -v -t $SESSION:0.1 -p 50
tmux send-keys -t $SESSION:0.2 'ssh graham-macbuntu "kubectl get events -n agent-execution -w"' C-m

# Select the Matrix pane
tmux select-pane -t $SESSION:0.0

# Attach to session
tmux attach-session -t $SESSION
EOF

chmod +x ~/start-guardian.sh

echo "✅ Provisioning Complete!"
echo "------------------------------------------"
echo "Next steps on Nexus 7:"
echo "1. Log in to your Macbuntu host via SSH once to accept keys."
echo "2. Run './start-guardian.sh' to launch the dashboard."
echo "3. In gomuks, log in to 'http://<MACBUNTU_IP>:8008' as '@graham:macbuntu.local'."
echo "------------------------------------------"
