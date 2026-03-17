#!/data/data/com.termux/files/usr/bin/bash

# ==========================================
# 🧪 Hardened Mobile Agent Lab (Chroot Edition)
# ==========================================
# This script manages the transition from Android (Termux) 
# to a secure Ubuntu chroot environment.
# ==========================================

# 1. Clean Mount Logic (Requires Root/Sudo in Termux)
# Note: We bind-mount the Android / to the chroot's /host
# to allow agents to see device stats (optional).
UBUNTU_ROOT="/data/local/ubuntu"

for m in proc sys dev dev/pts; do
    if ! grep -q "$UBUNTU_ROOT/$m" /proc/mounts; then
        mount --bind "/$m" "$UBUNTU_ROOT/$m"
    fi
done

# 2. Command Dispatcher (Security Architect Pattern)
# This prevents command injection by only allowing pre-defined actions.

ACTION=$1

case "$ACTION" in
    "audit")
        # ACTION: Security Audit (Forced System Persona)
        shift
        if [ -z "$1" ]; then
            # Read from stdin if no arguments (the "Robust Shoot" method)
            PROMPT=$(cat)
        else
            PROMPT="$*"
        fi
        
        echo "🛡️  Forwarding to Mobile Security Analyst (via Stdin)..."
        echo "$PROMPT" | chroot "$UBUNTU_ROOT" /bin/su - agent-lab -c \
            "source ~/venv/bin/activate && \
             llm -m qwen2.5-coder:1.5b \
             -s 'You are a Senior Security Auditor. Provide a concise Risk Level (Low/Med/High) followed by actionable mitigations for the following code or config.'"
        ;;

    "status")
        # ACTION: Device Health Check (No Prompt Required)
        echo "📊 Device Health (Inside Chroot):"
        chroot "$UBUNTU_ROOT" /bin/su - agent-lab -c "uptime && free -h"
        ;;

    "update")
        # ACTION: Maintain LLM Fleet
        echo "📥 Syncing LLM Models..."
        chroot "$UBUNTU_ROOT" /bin/su - agent-lab -c "ollama pull qwen2.5-coder:1.5b"
        ;;

    "")
        # DEFAULT: Interactive Shell (For manual work)
        echo "🏠 Entering Agent Lab (Interactive)..."
        chroot "$UBUNTU_ROOT" /bin/su - agent-lab
        ;;

    *)
        # REJECT: Block anything that isn't on the allow-list
        echo "🚫 ERROR: Unauthorized Agent Action: '$ACTION'"
        echo "Allowed actions: audit, status, update, (empty for shell)"
        exit 1
        ;;
esac
