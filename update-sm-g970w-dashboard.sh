#!/bin/bash

# Configuration for Samsung SM-G970W
DEVICE_IP="192.168.4.55"
SSH_USER="u0_a293"
SSH_PORT="8022"

SSH_KEY="~/.ssh/id_mobile_scout-sm-g970w"

echo "🚀 Updating Dashboard to V2 on Samsung SM-G970W ($DEVICE_IP)..."

# 1. Install dependencies (gotop)
echo "📦 Installing gotop in Termux..."
ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER@$DEVICE_IP "pkg update -y && pkg install gotop -y"

# 2. Create the new start-dashboard.sh script content
DASHBOARD_SCRIPT=$(cat << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
export OLLAMA_HOST=0.0.0.0

# Ensure SSH is running
pgrep sshd >/dev/null || sshd

# Kill any existing dashboard session
tmux kill-session -t agent-dashboard 2>/dev/null

# Start a new detached tmux session
tmux new-session -d -s agent-dashboard

# Top pane (0): gotop (Resource Monitor)
# We set gotop to take most of the screen
tmux send-keys -t agent-dashboard:0.0 "gotop" C-m

# Split vertically, giving the bottom pane about 30% of the space
# -v: vertical split (one above the other)
# -p 30: 30 percent for the new pane
tmux split-window -v -p 30 -t agent-dashboard:0

# Bottom pane (1): Active Inference Monitor
# This shows exactly what models are running
tmux send-keys -t agent-dashboard:0.1 "watch -n 2 'ollama ps'" C-m

# Select the top pane as active
tmux select-pane -t agent-dashboard:0.0

# Attach to session
tmux attach-session -t agent-dashboard
EOF
)

# 3. Push the new dashboard script
echo "📤 Uploading new start-dashboard.sh..."
echo "$DASHBOARD_SCRIPT" | ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER@$DEVICE_IP "cat > ~/start-dashboard.sh && chmod +x ~/start-dashboard.sh"

# 4. (Optional) Restart the dashboard
# If you are currently looking at the dashboard, this will close it.
echo "🔄 Restarting dashboard session..."
ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER@$DEVICE_IP "tmux kill-session -t agent-dashboard 2>/dev/null; ~/start-dashboard.sh &"

echo "✅ Dashboard V2 Update Complete!"
echo "You can now connect to the SM-G970W and run 'tmux a -t agent-dashboard' or just open Termux."
