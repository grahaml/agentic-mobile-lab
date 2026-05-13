#!/bin/bash
# test-swarm.sh - Multi-tool Swarm Verification Script

set -e

# Default values
TOOL=${1:-llm}
MODEL=${2:-mistral}
VENV_DIR="$HOME/.venv-private-runtime"

export OLLAMA_API_BASE="http://localhost:11434"

echo "🧪 Starting Swarm Test [Tool: $TOOL, Model: $MODEL]..."

case $TOOL in
  aider)
    echo "🤖 Running Aider..."
    $VENV_DIR/bin/aider \
      --model "ollama_chat/$MODEL" \
      --edit-format whole \
      --no-git \
      --message "Update 'swarm_hello.py' to say 'Hello from Native K3s!' in the docstring and print statement." \
      --yes
    ;;
  llm)
    echo "🧠 Running LLM CLI..."
    # llm-ollama discovered models don't need the ollama/ prefix
    $VENV_DIR/bin/llm -m "$MODEL" "Generate a 1-sentence Python script that prints 'Fast and light from K3s!'" > swarm_fast.py
    echo "✅ LLM generated swarm_fast.py"
    cat swarm_fast.py
    ;;
  *)
    echo "❌ Unknown tool: $TOOL. Use 'aider' or 'llm'."
    exit 1
    ;;
esac

echo "🚀 Running verification..."
if [ "$TOOL" == "aider" ]; then
    python3 swarm_hello.py
else
    # Clean up any markdown wrapping or explanatory text
    # This extract anything between ```python and ``` or just the first line with print
    if grep -q "```python" swarm_fast.py; then
        sed -n '/```python/,/```/p' swarm_fast.py | sed 's/```python//g; s/```//g' > swarm_fast.py.tmp
        mv swarm_fast.py.tmp swarm_fast.py
    elif grep -q "```" swarm_fast.py; then
        sed -n '/```/,/```/p' swarm_fast.py | sed 's/```//g' > swarm_fast.py.tmp
        mv swarm_fast.py.tmp swarm_fast.py
    fi
    python3 swarm_fast.py
fi

echo "🎉 Swarm Test Complete!"
