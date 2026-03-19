import subprocess
import sys
import time

# Configuration
# Usage: python3 test-ssh.py <SERVICE_NAME> <MODEL> <PROMPT> <USER>
service_name = sys.argv[1] if len(sys.argv) > 1 else 'scout-sm-g970w'
model_name = sys.argv[2] if len(sys.argv) > 2 else 'qwen2.5:0.5b'
prompt = sys.argv[3] if len(sys.argv) > 3 else 'Why is SSH better than HTTP for slow mobile AI nodes?'
user = sys.argv[4] if len(sys.argv) > 4 else "u0_a293" 

# We need the ClusterIP to talk to the phone through the Service
# (In a real pod, we'd use the DNS name)
host = f"{service_name}.agent-execution.svc.cluster.local"
port = "8022"

print(f"🚀 Launching SSH-based inference on {service_name}...")
print(f"📡 Target: {host}:{port}")
print(f"👤 User:   {user}")
print(f"🧠 Model:  {model_name}")

# This command runs inside the Termux environment on the phone
# We activate the venv and run the llm cli
# Note: Using ~/.venv-llm/bin/activate as per common setup
remote_cmd = f"source ~/.venv-llm/bin/activate && llm -m ollama/{model_name} '{prompt}'"

# SSH Command Construction
# -o ConnectTimeout=10: Don't wait forever to connect
# -o ServerAliveInterval=15: Keep the connection from falling asleep
ssh_cmd = [
    "ssh",
    "-p", port,
    "-o", "ConnectTimeout=10",
    "-o", "ServerAliveInterval=15",
    "-o", "StrictHostKeyChecking=no",
    "-i", "/root/.ssh/id_rsa",
    f"{user}@{host}",
    remote_cmd
]

start_time = time.time()
try:
    # We use check_output to capture the result
    result = subprocess.check_output(ssh_cmd, stderr=subprocess.STDOUT).decode('utf-8')
    duration = time.time() - start_time
    print(f"\n✅ SUCCESS ({duration:.1f}s)!")
    print("-" * 40)
    print(result)
    print("-" * 40)
except subprocess.CalledProcessError as e:
    print(f"❌ SSH Execution Failed (Exit Code {e.returncode})")
    print(f"Error: {e.output.decode() if e.output else 'Unknown'}")
except Exception as e:
    print(f"❌ System Error: {e}")
