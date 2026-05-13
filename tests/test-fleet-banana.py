import urllib.request
import json
import socket
import time
import sys
import argparse

# Configuration
namespace = "agent-execution"

def check_port(host, port):
    """Check if a specific port is open on a host."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(3)
        try:
            s.connect((host, port))
            return True
        except:
            return False

def get_available_models(svc_dns):
    """Query the Ollama API for available models on the node."""
    url = f"http://{svc_dns}:11434/api/tags"
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            if response.status == 200:
                data = json.loads(response.read().decode())
                return [m['name'] for m in data.get('models', [])]
    except Exception as e:
        return []
    return []

def test_inference(service_name, prompt, preferred_model=None):
    """Run an inference call against a scout service."""
    svc_dns = f"{service_name}.{namespace}.svc.cluster.local"
    
    if not check_port(svc_dns, 11434):
        return {"status": "OFFLINE", "response": "Port 11434 unreachable"}
    
    models = get_available_models(svc_dns)
    if not models:
        return {"status": "ERROR", "response": "No models found"}
    
    # Selection logic: preferred -> first available
    selected_model = preferred_model if preferred_model in models else models[0]
    
    url = f"http://{svc_dns}:11434/api/generate"
    payload = json.dumps({
        'model': selected_model,
        'prompt': prompt,
        'stream': False
    }).encode('utf-8')

    req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})

    try:
        start_time = time.time()
        # Set timeout to 120 seconds (2 minutes) as requested
        with urllib.request.urlopen(req, timeout=120) as response:
            duration = time.time() - start_time
            if response.status == 200:
                result = json.loads(response.read().decode())
                response_text = result.get('response', 'No response field')
                return {"status": "SUCCESS", "response": response_text.strip(), "duration": f"{duration:.1f}s", "model": selected_model}
            else:
                return {"status": "ERROR", "response": f"HTTP {response.status}"}
    except socket.timeout:
        return {"status": "TIMEOUT", "response": "Request timed out (>120s)"}
    except Exception as e:
        return {"status": "ERROR", "response": str(e)}

def main():
    parser = argparse.ArgumentParser(description="Cluster Mobile Fleet Audit")
    parser.add_argument("services", nargs="+", help="Names of services to test")
    parser.add_argument("--prompt", default="I am a banana", help="Prompt to send")
    parser.add_argument("--model", help="Preferred Ollama model")
    
    args = parser.parse_args()
    
    results = []
    for svc in args.services:
        res = test_inference(svc, args.prompt, args.model)
        res["node"] = svc
        results.append(res)
    
    print(json.dumps(results))

if __name__ == "__main__":
    main()
