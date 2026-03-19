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
pkg update -y && pkg upgrade -y
# Install all required native tools
pkg install ollama python git openssh gh rust binutils build-essential clang tmux htop -y

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
ollama serve > /dev/null 2>&1 &
SLEEP_PID=$!
sleep 5
# Check if llm can see the models
"$VENV_PATH/bin/llm" models list | grep "ollama" || echo "⚠️ Ollama models not detected yet."

# 5. Dashboard Configuration
echo "🪟 Configuring Tmux dashboard..."
cat << 'EOF' > "$HOME/start-dashboard.sh"
#!/bin/bash
# Start a new detached tmux session
tmux new-session -d -s agent-dashboard

# Split vertically
tmux split-window -v -p 30 -t agent-dashboard:0
# Split bottom pane horizontally
tmux split-window -h -p 50 -t agent-dashboard:0.1

# Top pane (0): htop
tmux send-keys -t agent-dashboard:0.0 "htop" C-m

# Bottom-left pane (1): Ollama server
tmux send-keys -t agent-dashboard:0.1 "export OLLAMA_HOST=0.0.0.0; ollama serve" C-m

# Bottom-right pane (2): Venv and readiness
tmux send-keys -t agent-dashboard:0.2 "source ~/.venv-llm/bin/activate; echo 'Dashboard Ready!'; ifconfig | grep -E 'inet .*wlan'" C-m

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
