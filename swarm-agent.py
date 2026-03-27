import uuid
import base64
import argparse
from kubernetes import client, config, watch

def get_mobile_nodes(namespace="agent-execution"):
    """Query Kubernetes for available services in the given namespace."""
    try:
        v1 = client.CoreV1Api()
        services = v1.list_namespaced_service(namespace=namespace)
        # Returns the names of all services found
        return [svc.metadata.name for svc in services.items]
    except Exception as e:
        print(f"⚠️ Error fetching services: {e}")
        return []

def generate_in_pod_script(device_name, prompt):
    host = f"{device_name}.agent-execution.svc.cluster.local"
    port = 11434
    
    # Securely pass prompt to pod script
    encoded_prompt = base64.b64encode(prompt.encode('utf-8')).decode('utf-8')
    
    # This Python code runs INSIDE the pod
    return f"""
import urllib.request
import json
import base64

def run():
    try:
        host = "{host}"
        port = {port}
        
        # 1. Fetch available models dynamically
        tags_url = f"http://{{host}}:{{port}}/api/tags"
        print(f"🔍 Fetching available models from {{tags_url}}...")
        req = urllib.request.Request(tags_url)
        with urllib.request.urlopen(req, timeout=10) as response:
            tags_data = json.loads(response.read().decode('utf-8'))
            models = [m['name'] for m in tags_data.get('models', [])]
            
        if not models:
            print("❌ No models found on this node.")
            return
            
        selected_model = models[0]
        print(f"📦 Selected model: {{selected_model}}")
        
        # 2. Run inference
        url = f"http://{{host}}:{{port}}/api/generate"
        prompt_text = base64.b64decode("{encoded_prompt}").decode('utf-8')
        payload = {{
            "model": selected_model,
            "prompt": prompt_text,
            "stream": False
        }}
        
        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(url, data=data, headers={{'Content-Type': 'application/json'}})
        
        print(f"🚀 Executing HTTP inference on {device_name} (http://{{host}}:{{port}})...")
        
        with urllib.request.urlopen(req, timeout=600) as response:
            result = json.loads(response.read().decode('utf-8'))
            print("\\n--- INFERENCE RESULT ---")
            print(result.get("response", ""))
            print("-------------------------")
            
    except Exception as e:
        print(f"❌ Fatal Pod Error: {{e}}")

if __name__ == '__main__':
    run()
"""

def deploy_agent_pod(device_name, prompt):
    v1 = client.CoreV1Api()
    
    job_id = f"agent-{device_name}-{uuid.uuid4().hex[:4]}"
    namespace = "agent-execution"
    
    in_pod_python = generate_in_pod_script(device_name, prompt)
    encoded_python = base64.b64encode(in_pod_python.encode()).decode()
    
    pod_spec = client.V1Pod(
        metadata=client.V1ObjectMeta(name=job_id, labels={"app": "swarm-agent", "device": device_name}),
        spec=client.V1PodSpec(
            service_account_name="agent-executor-sa",
            restart_policy="Never",
            containers=[
                client.V1Container(
                    name="agent",
                    image="python:3-alpine", # Using a standard lightweight python image
                    command=["python3", "-u", "-c", f"import base64; exec(base64.b64decode('{encoded_python}'))"],
                    resources=client.V1ResourceRequirements(
                        limits={"cpu": "500m", "memory": "256Mi"}
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
    # Initialize Kubernetes client first to discover devices dynamically
    try:
        config.load_kube_config()
    except Exception as e:
        print(f"❌ Failed to load Kubernetes config: {e}")
        exit(1)
        
    available_devices = get_mobile_nodes()

    parser = argparse.ArgumentParser(description="Dynamic Agent Swarm Executor (HTTP)")
    # Restrict choices to the dynamically discovered devices if successful
    parser.add_argument("--device", required=True, choices=available_devices if available_devices else None, help="Target mobile node service name in agent-execution namespace")
    parser.add_argument("--prompt", required=True, help="Prompt for the mobile model")
    
    args = parser.parse_args()
    deploy_agent_pod(args.device, args.prompt)