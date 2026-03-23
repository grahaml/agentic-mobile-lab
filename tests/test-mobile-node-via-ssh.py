#!/usr/bin/env python3
"""
🧪 Secure Mobile Node SSH Test Runner
Verifies model inference on mobile nodes via SSH.
Supports both chroot (rooted) and direct (unrooted) modes.
"""

import argparse
import subprocess
import sys
import time
import shlex
import os

# --- Security: Whitelisted Device Metadata ---
# This serves as the initial "Platform Capability" [APP-003]
# Prevents SSRF/Scanning by only allowing known service names.
DEVICE_METADATA = {
    "scout-s10e": {
        "user": "u0_a293",
        "port": 8022,
        "host": "scout-s10e.agent-execution.svc.cluster.local",
        "mode": "direct",
        "model": "qwen2.5:0.5b"
    },
    "scout-motorolaedge2023": {
        "user": "u0_a293",
        "port": 8022,
        "host": "scout-motorolaedge2023.agent-execution.svc.cluster.local",
        "mode": "chroot",
        "model": "qwen2.5-coder:1.5b"
    }
}

def resolve_device_metadata(device_name):
    """Securely resolves device metadata from the whitelist."""
    if device_name not in DEVICE_METADATA:
        print(f"❌ Error: Device '{device_name}' is not in the authorized whitelist.")
        print(f"Available devices: {', '.join(DEVICE_METADATA.keys())}")
        sys.exit(1)
    return DEVICE_METADATA[device_name]

def run_ssh_inference(device_name, prompt, user_override=None, port_override=None, mode_override=None):
    metadata = resolve_device_metadata(device_name)
    
    host = metadata["host"]
    user = user_override or metadata["user"]
    port = str(port_override or metadata["port"])
    mode = mode_override or metadata["mode"]
    model = metadata.get("model", "qwen2.5:0.5b")
    
    # --- Security: Prevent Shell Injection ---
    sanitized_prompt = shlex.quote(prompt)
    
    if mode == "chroot":
        # The remote command calls 'enter_lab.sh audit' which handles the model interaction.
        # Note: Rooted devices might need sudo/su if sshd runs as termux user.
        # We assume enter_lab.sh is in the home dir.
        remote_command = f"~/enter_lab.sh audit {sanitized_prompt}"
    else:
        # Direct mode for unrooted devices (like S10e)
        # We use the venv installed during mobile-agent-setup.sh
        remote_command = f"~/.venv-llm/bin/llm -m {model} {sanitized_prompt}"

    # SSH Command Construction (List format for subprocess safety)
    ssh_cmd = [
        "ssh",
        "-p", port,
        "-o", "ConnectTimeout=15",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        f"{user}@{host}",
        remote_command
    ]

    print(f"🚀 [SSH] Targeting: {device_name} ({host}:{port})")
    print(f"👤 [USER] {user}")
    print(f"🛠️  [MODE] {mode}")
    print(f"🧠 [CMD]  {remote_command[:60]}...")
    print("-" * 40)

    start_time = time.time()
    try:
        # Run the command and capture output
        result = subprocess.run(
            ssh_cmd, 
            capture_output=True, 
            text=True, 
            check=True,
            timeout=180 # 3 minute timeout for model inference
        )
        duration = time.time() - start_time
        
        print(f"\n✅ SUCCESS ({duration:.1f}s)!")
        print("-" * 40)
        print(result.stdout.strip())
        print("-" * 40)
        
    except subprocess.TimeoutExpired:
        print(f"❌ Error: Inference timed out after 180 seconds.")
    except subprocess.CalledProcessError as e:
        print(f"❌ SSH Execution Failed (Exit Code {e.returncode})")
        if e.stderr:
            print(f"Error Details: {e.stderr.strip()}")
        if e.stdout:
            print(f"Partial Output: {e.stdout.strip()}")
    except Exception as e:
        print(f"❌ System Error: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Secure Mobile Node SSH Test Runner")
    parser.add_argument("--device", required=True, help="Target device name (e.g., scout-s10e)")
    parser.add_argument("--prompt", required=True, help="Prompt to send to the model")
    parser.add_argument("--user", help="Override the SSH user")
    parser.add_argument("--port", type=int, help="Override the SSH port")
    parser.add_argument("--mode", choices=["chroot", "direct"], help="Override the test mode")

    args = parser.parse_args()

    run_ssh_inference(
        device_name=args.device,
        prompt=args.prompt,
        user_override=args.user,
        port_override=args.port,
        mode_override=args.mode
    )
