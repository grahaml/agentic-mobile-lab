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
pkg install ollama python git openssh gh rust binutils build-essential clang -y || (apt update && apt install -y ollama python git openssh gh rust binutils build-essential clang)

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

# 5. Configure Termux:Boot startup script
echo "🚀 Configuring Termux:Boot startup script..."
mkdir -p "$HOME/.termux/boot"
cat << 'EOF' > "$HOME/.termux/boot/start-agent"
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sshd
OLLAMA_HOST=0.0.0.0 OLLAMA_MAX_LOADED_MODELS=1 ollama serve > "$HOME/ollama.log" 2>&1 &
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
