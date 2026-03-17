#!/bin/bash
# test-aider-swarm.sh - End-to-End Test for Private Agent Runtime

echo "🧪 Starting End-to-End Swarm Test..."

# 1. Environment Configuration
VENV_DIR="$HOME/.venv-private-runtime"
MODEL_NAME="mistral"
export OLLAMA_API_BASE="http://localhost:11434"
export AIDER_DARK_MODE="true"
export AIDER_CHECK_UPDATE="false"

# 2. Command Execution
echo "🤖 Instructing Aider to create a hello world script using local Mistral..."

# Using architect mode with a 7B model often yields much better results
$VENV_DIR/bin/aider \
  --model "ollama_chat/$MODEL_NAME" \
  --edit-format whole \
  --no-git \
  --message "Create a simple Python script named 'swarm_hello.py' that prints 'Hello from the Private Swarm!' and include a small docstring explaining it's running in k3d." \
  --yes

# 3. Verification
if [ -f "swarm_hello.py" ]; then
    echo "✅ SUCCESS: Aider created the file!"
    echo "--- File Content ---"
    cat swarm_hello.py
    echo "-------------------"
    echo "🚀 Running the generated script..."
    python3 swarm_hello.py
else
    echo "❌ FAILURE: Aider did not create the file."
    exit 1
fi

echo "🎉 E2E Swarm Test Complete!"
