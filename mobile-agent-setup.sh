#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
# 📱 Mobile Agent Lab: Bootstrap Script (Termux)
# ==========================================
# Optimized for: Motorola Edge 2023 (houston)
# Target Stack: Ollama, Aider, Zellij, Python 3.11+
# ==========================================

set -e

# Configuration
MODEL_NAME="qwen2.5:0.5b" # CPU/RAM friendly for 8GB devices
ZELLIJ_LAYOUT_DIR="$HOME/.config/zellij/layouts"
VENV_DIR="$HOME/.venv-agent-lab"

echo "🚀 Initializing Mobile Agent Lab for Termux..."

# 1. Core Package Updates
echo "📦 Updating Termux repositories..."
pkg update -y && pkg upgrade -y

# 2. Dependency Installation
echo "📦 Installing core dependencies..."
# tur-repo provides code-server and other optimized tools
pkg install tur-repo -y
pkg install ollama python git pip zellij build-essential binutils openssh gh -y

# 3. Python Environment Setup
echo "🐍 Setting up Python Virtual Environment..."
if [ -d "$VENV_DIR" ]; then
    echo "⚠️  Venv exists, updating..."
else
    python -m venv "$VENV_DIR"
fi

echo "📦 Installing Agentic Stack (Aider, Discord.py)..."
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install aider-chat discord.py

# 4. Zellij Layout Configuration
echo "🪟 Configuring Zellij layout..."
mkdir -p "$ZELLIJ_LAYOUT_DIR"

cat <<EOF > "$ZELLIJ_LAYOUT_DIR/agent-lab.kdl"
layout {
    pane split_direction="vertical" {
        pane name="Ollama Engine" command="ollama" {
            args "serve"
        }
        pane name="Aider (The Architect)" {
            command "$VENV_DIR/bin/aider"
            args "--model" "ollama/$MODEL_NAME"
        }
    }
    pane size=1 borderless=true {
        plugin location="zellij:status-bar"
    }
}
EOF

# 5. Bootstrapping the Local Model
echo "🧠 Pre-loading the LLM ($MODEL_NAME)..."
# Start Ollama in background just to pull the model
ollama serve > /dev/null 2>&1 &
SLEEP_PID=$!
sleep 5
ollama pull "$MODEL_NAME"
kill $SLEEP_PID || true

# 6. Final Instructions
echo ""
echo "=========================================="
echo "🎉 MOBILE AGENT LAB READY! 🎉"
echo "=========================================="
echo "1. Important: Ensure you've run the 'Phantom Process' fix via ADB on your PC."
echo "2. Keep Alive: Tap 'Acquire Wake Lock' in the Termux notification bar."
echo "3. Launch: Run the command below to start your integrated workspace:"
echo ""
echo "   zellij --layout agent-lab"
echo ""
echo "To manually use Aider later:"
echo "   source $VENV_DIR/bin/activate && aider"
echo "=========================================="
