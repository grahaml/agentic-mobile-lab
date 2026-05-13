import uuid
import time
from kubernetes import client, config, watch

import base64

def execute_in_sandbox(python_code, image="python:3.12-slim"):
    """
    Spins up a transient Pod in the agent-execution namespace to run provided code.
    """
    config.load_kube_config()
    v1 = client.CoreV1Api()
    
    job_id = f"exec-{uuid.uuid4().hex[:6]}"
    namespace = "agent-execution"
    
    # Encode code to base64 to avoid shell escape issues
    encoded_code = base64.b64encode(python_code.encode()).decode()
    cmd = f"import base64; exec(base64.b64decode('{encoded_code}'))"

    # Define the Pod Spec
    pod_spec = client.V1Pod(
        metadata=client.V1ObjectMeta(name=job_id, labels={"app": "swarm-executor"}),
        spec=client.V1PodSpec(
            restart_policy="Never",
            containers=[
                client.V1Container(
                    name="executor",
                    image=image,
                    command=["python3", "-c", cmd],
                    resources=client.V1ResourceRequirements(
                        limits={"cpu": "200m", "memory": "256Mi"}
                    )
                )
            ]
        )
    )

    print(f"🛡️  Deploying sandbox pod {job_id}...")
    v1.create_namespaced_pod(namespace=namespace, body=pod_spec)

    # Watch for completion and stream logs
    print(f"⏳ Waiting for execution results...")
    w = watch.Watch()
    for event in w.stream(v1.list_namespaced_pod, namespace=namespace, label_selector=f"app=swarm-executor"):
        pod = event['object']
        if pod.metadata.name == job_id:
            if pod.status.phase in ["Succeeded", "Failed"]:
                try:
                    logs = v1.read_namespaced_pod_log(name=job_id, namespace=namespace)
                    print("\n--- SANDBOX OUTPUT ---")
                    print(logs)
                    print("----------------------")
                except Exception as e:
                    print(f"⚠️  Could not read logs: {e}")
                w.stop()
                break

    # Cleanup
    print(f"🧹 Cleaning up pod {job_id}...")
    v1.delete_namespaced_pod(name=job_id, namespace=namespace)

import os

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if os.path.isfile(arg):
            with open(arg, 'r') as f:
                test_code = f.read()
        else:
            test_code = arg
    else:
        test_code = "import platform; print(f'Hello from {platform.system()} inside the K3d Sandbox!')"
    
    execute_in_sandbox(test_code)
