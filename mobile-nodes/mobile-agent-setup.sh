#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
# 📱 Mobile Agent Lab: Scout Edition (Venv/Safe)
# ==========================================
# This version uses a Python Virtual Environment to 
# comply with PEP 668 (Externally Managed Environments).
# ==========================================

set -e

# Configuration
TERMUX_PREFIX="/data/data/com.termux/files/usr"
export PATH="$TERMUX_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$TERMUX_PREFIX/lib"
export ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-31}"

MODEL_NAME="qwen2.5:0.5b"
ZELLIJ_LAYOUT_DIR="$HOME/.config/zellij/layouts"
VENV_PATH="$HOME/.venv-llm"

echo "🚀 Initializing Mobile Agent Lab (Venv Scout Edition)..."

# 1. Core Package Updates & Build Tools
echo "📦 Updating Termux and installing build tools..."
pkg update -y && pkg upgrade -y || (pkg update -y && pkg upgrade -y -f)
# Install all required native tools
pkg install root-repo -y || true
pkg install ollama python git openssh gh rust binutils build-essential clang tmux btop viddy syncthing -y || (apt update && apt install -y ollama python git openssh gh rust binutils build-essential clang tmux btop viddy syncthing)

# Prevent CPU sleep
echo "🛡️  Acquiring Termux CPU Wake Lock..."
termux-wake-lock || true

# 2. Setup Virtual Environment (The "Safe" Way)
echo "🐍 Creating virtual environment at $VENV_PATH..."
if [ -d "$VENV_PATH" ]; then
    echo "⚠️ Venv already exists, updating..."
else
    python -m venv "$VENV_PATH"
fi

# 3. Install LLM inside the Venv
echo "⚙️ Tuning environment for native compilation..."
export CARGO_BUILD_TARGET=$(rustc -Vv | grep "host" | awk '{print $2}')

echo "🐍 Installing 'llm' and 'llm-ollama' (this may take 3-5 mins)..."
# We use the venv's pip to avoid the "forbidden" error
"$VENV_PATH/bin/pip" install --upgrade pip
"$VENV_PATH/bin/pip" install llm llm-ollama

# 4. Configure LLM to see Ollama
echo "🧠 Registering Ollama models..."
pkill ollama || true
export OLLAMA_HOST=0.0.0.0
export OLLAMA_MAX_LOADED_MODELS=1
ollama serve > /dev/null 2>&1 &
SLEEP_PID=$!
sleep 5
# Check if llm can see the models
"$VENV_PATH/bin/llm" models list | grep "ollama" || echo "⚠️ Ollama models not detected yet."

# 5. Dashboard Configuration (V2: Observability & Persistence)
echo "🪟 Configuring Tmux dashboard (V2)..."
cat << 'EOF' > "$HOME/start-dashboard.sh"
#!/data/data/com.termux/files/usr/bin/bash

# Ensure SSH is running
pgrep sshd >/dev/null || sshd

# Ensure Ollama is running with API accessible to cluster (0.0.0.0)
if ! pgrep ollama >/dev/null; then
    echo "Starting Ollama..."
    export OLLAMA_HOST=0.0.0.0
    export OLLAMA_MAX_LOADED_MODELS=1
    ollama serve > "$HOME/ollama.log" 2>&1 &
    sleep 5
fi

# Ensure Syncthing is running
if ! pgrep syncthing >/dev/null; then
    echo "Starting Syncthing..."
    syncthing --no-browser > "$HOME/syncthing.log" 2>&1 &
fi

# Start a new detached tmux session
tmux has-session -t agent-dashboard 2>/dev/null
if [ $? != 0 ]; then
    tmux new-session -d -s agent-dashboard

    # Top pane (0): btop (Resource Monitor)
    tmux send-keys -t agent-dashboard:0.0 "btop" C-m

    # Split vertically (Pane 1 at 70% down)
    tmux split-window -v -p 30 -t agent-dashboard:0.0

    # Bottom pane (1): Active Inference Monitor
    tmux send-keys -t agent-dashboard:0.1 "viddy -n 2 'ollama ps && syncthing device id'" C-m
fi

# Attach to session
tmux attach-session -t agent-dashboard
EOF
chmod +x "$HOME/start-dashboard.sh"

# Auto-launch on open
if ! grep -q "start-dashboard.sh" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# Auto-start dashboard if not in tmux" >> "$HOME/.bashrc"
    echo 'if [ -z "$TMUX" ]; then' >> "$HOME/.bashrc"
    echo '    ~/start-dashboard.sh' >> "$HOME/.bashrc"
    echo 'fi' >> "$HOME/.bashrc"
fi

# 5b. Configure Termux:Boot startup script
echo "🚀 Configuring Termux:Boot startup script..."
mkdir -p "$HOME/.termux/boot"
cat << 'EOF' > "$HOME/.termux/boot/start-agent"
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sshd
~/start-dashboard.sh
EOF
chmod +x "$HOME/.termux/boot/start-agent"

# 6. Bootstrapping the Local Model
echo "📥 Pulling $MODEL_NAME..."
ollama pull "$MODEL_NAME"
kill $SLEEP_PID || true

# 7. Final Instructions
echo ""
echo "=========================================="
echo "🎉 MOBILE AGENT LAB READY (Safe Venv)! 🎉"
echo "=========================================="
echo "1. Start Ollama: ollama serve &"
echo "2. Use the Agent:"
echo "   source $VENV_PATH/bin/activate"
echo "   llm -m ollama/$MODEL_NAME \"Hello!\""
echo "=========================================="
