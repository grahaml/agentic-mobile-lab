#!/data/data/com.termux/files/usr/bin/bash
# Creates (or reattaches to) the fleet rack display tmux session.
#
# Called from Termux:Boot: creates session in background, does NOT attach.
# Called from wake-fleet-displays.sh or manually: creates session if needed, then attaches.

export PATH="/data/data/com.termux/files/usr/bin:$PATH"

SESSION="display"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux new-session -d -s "$SESSION"
    tmux send-keys -t "$SESSION:0" "python3 $HOME/telemetry/device_dashboard.py" C-m
fi

# Attach only when running in a terminal (not from Termux:Boot background)
[ -t 0 ] && tmux attach-session -t "$SESSION"
