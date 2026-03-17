#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
# 📱 Mobile Agent Lab: Scout Edition (Venv/Safe)
# ==========================================
# This version uses a Python Virtual Environment to 
# comply with PEP 668 (Externally Managed Environments).
# ==========================================

set -e

# Configuration
MODEL_NAME="qwen2.5:0.5b"
ZELLIJ_LAYOUT_DIR="$HOME/.config/zellij/layouts"
VENV_PATH="$HOME/.venv-llm"

echo "🚀 Initializing Mobile Agent Lab (Venv Scout Edition)..."

# 1. Core Package Updates & Build Tools
echo "📦 Updating Termux and installing build tools..."
pkg update -y && pkg upgrade -y
# Install all required native tools
pkg install ollama python git zellij openssh gh rust binutils build-essential clang -y

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
ollama serve > /dev/null 2>&1 &
SLEEP_PID=$!
sleep 5
# Check if llm can see the models
"$VENV_PATH/bin/llm" models list | grep "ollama" || echo "⚠️ Ollama models not detected yet."

# 5. Zellij Layout Configuration
echo "🪟 Configuring Zellij layout..."
mkdir -p "$ZELLIJ_LAYOUT_DIR"

cat <<EOF > "$ZELLIJ_LAYOUT_DIR/agent-lab.kdl"
layout {
    pane split_direction="vertical" {
        pane name="Ollama Engine" command="ollama" {
            args "serve"
        }
        pane name="Scout Agent (llm)" {
            # This pane starts with the venv activated
            command "bash"
            args "-c" "source $VENV_PATH/bin/activate && exec bash"
        }
    }
    pane size=1 borderless=true {
        plugin location="zellij:status-bar"
    }
}
EOF

# 6. Bootstrapping the Local Model
echo "📥 Pulling $MODEL_NAME..."
ollama pull "$MODEL_NAME"
kill $SLEEP_PID || true

# 7. Final Instructions
echo ""
echo "=========================================="
echo "🎉 MOBILE AGENT LAB READY (Safe Venv)! 🎉"
echo "=========================================="
echo "1. Launch: zellij --layout agent-lab"
echo ""
echo "2. The 'Scout' pane will have your environment pre-activated."
echo "   Just try: llm -m ollama/$MODEL_NAME \"Hello!\""
echo "=========================================="
