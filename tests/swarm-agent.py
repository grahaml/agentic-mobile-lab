import uuid
import base64
import argparse
import os
import yaml
import time
import hashlib
import requests
from datetime import datetime
from kubernetes import client, config, watch

# Path to the synced Syncthing directory inside the pod
VAULT_INBOX = "/vault/inbox"

def get_env_hash():
    """Computes a hash of the environment to detect drift."""
    try:
        # Simplified: just hash the file itself and some env vars
        # In a real scenario, you'd hash pip freeze and model checksums
        env_str = f"{os.getenv('HOSTNAME')}-{os.getenv('PYTHON_VERSION')}"
        return hashlib.sha256(env_str.encode()).hexdigest()[:8]
    except:
        return "unknown"

def generate_in_pod_script(device_name, prompt):
    # (Keep existing in-pod script logic for actual inference)
    # This is still useful as the 'execution engine' called by the worker loop
    pass 

def process_vault_tasks(device_name):
    """The main loop for a worker node watching its Syncthing inbox."""
    inbox_path = VAULT_INBOX # This is mounted via Syncthing
    env_hash = get_env_hash()
    nonce = f"{device_name}-{uuid.uuid4().hex[:4]}"
    
    print(f"🤖 Swarm Worker '{device_name}' starting loop. Env: {env_hash}")
    
    while True:
        if not os.path.exists(inbox_path):
            os.makedirs(inbox_path, exist_ok=True)
            
        tasks = [f for f in os.listdir(inbox_path) if f.startswith("task-") and f.endswith(".md") and not f.endswith(".result.md")]
        
        for task_file in tasks:
            full_path = os.path.join(inbox_path, task_file)
            try:
                with open(full_path, "r") as f:
                    content = f.read()
                
                parts = content.split("---")
                if len(parts) < 3: continue
                
                metadata = yaml.safe_load(parts[1])
                if metadata.get("status") != "pending" or metadata.get("processing_nonce"):
                    continue
                
                # --- CLAIM TASK ---
                print(f"📥 Claiming task {task_file}...")
                metadata["status"] = "processing"
                metadata["processing_nonce"] = nonce
                metadata["worker_env_hash"] = env_hash
                
                # Update the file with the nonce (soft claim)
                new_content = f"---\n{yaml.dump(metadata)}---\n{parts[2]}"
                with open(full_path, "w") as f:
                    f.write(new_content)
                
                # --- EXECUTE TASK ---
                payload = parts[2].strip()
                print(f"🚀 Executing task: {metadata['task_id']}")
                
                # Internal routing to local Ollama (assuming sibling service)
                host = f"{device_name}.agent-execution.svc.cluster.local"
                url = f"http://{host}:11434/api/generate"
                
                response = requests.post(url, json={
                    "model": "qwen2.5:0.5b", # Fallback default
                    "prompt": payload,
                    "stream": False
                }, timeout=300)
                
                result_text = response.json().get("response", "Error: No response from model.")
                
                # --- WRITE RESULT ---
                result_filename = task_file.replace(".md", ".result.md")
                result_path = os.path.join(inbox_path, result_filename)
                
                result_metadata = metadata.copy()
                result_metadata["status"] = "complete"
                result_metadata["completed_at"] = datetime.utcnow().isoformat() + "Z"
                
                result_content = f"---\n{yaml.dump(result_metadata)}---\n\n{result_text}"
                with open(result_path, "w") as f:
                    f.write(result_content)
                
                print(f"✅ Task {metadata['task_id']} complete. Result at {result_filename}")
                
            except Exception as e:
                print(f"❌ Error processing {task_file}: {e}")
                
        time.sleep(10)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True)
    parser.add_argument("--mode", choices=["direct", "vault"], default="vault")
    args = parser.parse_args()
    
    if args.mode == "vault":
        process_vault_tasks(args.device)
    else:
        # Legacy direct mode logic...
        pass