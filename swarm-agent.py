import uuid
import time
import base64
import argparse
import sys
import os
import shlex
from kubernetes import client, config, watch

# --- Device Registry (Platform Capability) ---
DEVICE_METADATA = {
    "scout-s10e": {
        "user": "u0_a293",
        "port": 8022,
        "host": "scout-s10e.agent-execution.svc.cluster.local",
        "mode": "direct",
        "model": "mistral",
        "secret": "scout-s10e-ssh-key",
        "key_field": "id_mobile_scout-s10e"
    },
    "scout-motorolaedge2023": {
        "user": "u0_a293",
        "port": 8022,
        "host": "scout-motorolaedge2023.agent-execution.svc.cluster.local",
        "mode": "chroot",
        "model": "mistral",
        "secret": "scout-motorolaedge2023-ssh-key",
        "key_field": "id_mobile_scout-motorolaedge2023"
    }
}

def generate_in_pod_script(device_name, prompt):
    metadata = DEVICE_METADATA[device_name]
    secret_name = metadata["secret"]
    key_field = metadata["key_field"]
    user = metadata["user"]
    host = metadata["host"]
    port = metadata["port"]
    mode = metadata["mode"]
    model = metadata["model"]
    
    sanitized_prompt = shlex.quote(prompt)
    
    if mode == "chroot":
        remote_cmd = f"~/enter_lab.sh audit {sanitized_prompt}"
    else:
        remote_cmd = f"~/.venv-llm/bin/llm -m {model} {sanitized_prompt}"

    # This Python code runs INSIDE the pod
    return f"""
import base64
import os
import subprocess
from kubernetes import client, config

def run():
    try:
        print("🔐 Fetching SSH secret via RBAC...")
        config.load_incluster_config()
        v1 = client.CoreV1Api()
        
        secret = v1.read_namespaced_secret(name="{secret_name}", namespace="agent-execution")
        key_data = base64.b64decode(secret.data["{key_field}"])
        
        key_path = "/dev/shm/id_rsa"
        with open(key_path, "wb") as f:
            f.write(key_data)
        os.chmod(key_path, 0o400)
        
        print("🚀 Executing SSH inference on {device_name}...")
        ssh_cmd = [
            "ssh", "-i", key_path,
            "-p", "{port}",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "{user}@{host}",
            "{remote_cmd}"
        ]
        
        result = subprocess.run(ssh_cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            print("\\n--- INFERENCE RESULT ---")
            print(result.stdout)
            print("-------------------------")
        else:
            print(f"❌ SSH Failed (Code {{result.returncode}})")
            print(result.stderr)
            
    except Exception as e:
        print(f"❌ Fatal Pod Error: {{e}}")
    finally:
        if os.path.exists("/dev/shm/id_rsa"):
            os.remove("/dev/shm/id_rsa")
            print("🧹 SSH Key wiped from RAM.")

if __name__ == '__main__':
    run()
"""

def deploy_agent_pod(device_name, prompt):
    config.load_kube_config()
    v1 = client.CoreV1Api()
    
    job_id = f"agent-{device_name}-{uuid.uuid4().hex[:4]}"
    namespace = "agent-execution"
    
    in_pod_python = generate_in_pod_script(device_name, prompt)
    encoded_python = base64.b64encode(in_pod_python.encode()).decode()
    
    # Use the debug-agent:ssh image as it has 'ssh' and 'kubernetes' python lib installed
    pod_spec = client.V1Pod(
        metadata=client.V1ObjectMeta(name=job_id, labels={"app": "swarm-agent", "device": device_name}),
        spec=client.V1PodSpec(
            service_account_name="agent-executor-sa",
            restart_policy="Never",
            containers=[
                client.V1Container(
                    name="agent",
                    image="debug-agent:ssh", # Pre-baked with SSH and Kubernetes Python client
                    command=["python3", "-c", f"import base64; exec(base64.b64decode('{encoded_python}'))"],
                    resources=client.V1ResourceRequirements(
                        limits={"cpu": "500m", "memory": "512Mi"}
                    )
                )
            ]
        )
    )

    print(f"🛡️  Deploying Dynamic Agent Pod: {job_id}")
    v1.create_namespaced_pod(namespace=namespace, body=pod_spec)

    print(f"⏳ Waiting for agent results...")
    w = watch.Watch()
    try:
        for event in w.stream(v1.list_namespaced_pod, namespace=namespace, label_selector=f"app=swarm-agent"):
            pod = event['object']
            if pod.metadata.name == job_id:
                if pod.status.phase in ["Succeeded", "Failed"]:
                    logs = v1.read_namespaced_pod_log(name=job_id, namespace=namespace)
                    print("\n--- AGENT POD LOGS ---")
                    print(logs)
                    print("----------------------")
                    w.stop()
                    break
    except Exception as e:
        print(f"⚠️ Error watching pod: {e}")
    finally:
        print(f"🧹 Cleaning up pod {job_id}...")
        v1.delete_namespaced_pod(name=job_id, namespace=namespace)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Dynamic Agent Swarm Executor")
    parser.add_argument("--device", required=True, choices=DEVICE_METADATA.keys(), help="Target mobile node")
    parser.add_argument("--prompt", required=True, help="Prompt for the mobile model")
    
    args = parser.parse_args()
    deploy_agent_pod(args.device, args.prompt)
