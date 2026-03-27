import urllib.request
import json
import socket
import time
import sys
import argparse

# Configuration
namespace = "agent-execution"
test_prompt = "Tell me one thing about decentralized AI on mobile phones."

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
        print(f"  ❌ Failed to fetch models from {url}: {e}")
    return []

def test_inference(service_name, preferred_model=None):
    """Run an inference call against a scout service."""
    svc_dns = f"{service_name}.{namespace}.svc.cluster.local"
    
    print(f"\n🚀 Testing scout node: {service_name} ({svc_dns})")
    
    if not check_port(svc_dns, 11434):
        print(f"  ❌ Port 11434 is CLOSED or UNREACHABLE on {svc_dns}.")
        return False
    
    models = get_available_models(svc_dns)
    if not models:
        print(f"  ❌ No models found on {service_name}.")
        return False
    
    # Selection logic: preferred -> first available
    selected_model = preferred_model if preferred_model in models else models[0]
    print(f"  📦 Selected model: {selected_model} (Available: {', '.join(models)})")
    
    url = f"http://{svc_dns}:11434/api/generate"
    payload = json.dumps({
        'model': selected_model,
        'prompt': test_prompt,
        'stream': False
    }).encode('utf-8')

    req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})

    try:
        print(f"  🛰️  Calling API: {url}")
        start_time = time.time()
        with urllib.request.urlopen(req, timeout=300) as response:
            duration = time.time() - start_time
            if response.status == 200:
                result = json.loads(response.read().decode())
                response_text = result.get('response', 'No response field')
                print(f"  ✅ SUCCESS ({duration:.1f}s)!")
                print("  " + "-" * 40)
                for line in response_text.strip().splitlines():
                    print(f"  | {line}")
                print("  " + "-" * 40)
                return True
            else:
                print(f"  ❌ API Error: HTTP {response.status}")
    except Exception as e:
        print(f"  ❌ Network/API Error: {e}")
    return False

def main():
    parser = argparse.ArgumentParser(description="Cluster Mobile Scout Fleet Audit (Model-Aware)")
    parser.add_argument("services", nargs="*", help="Names of scout services to test (if empty, tests all found in cluster)")
    parser.add_argument("--model", help="Preferred Ollama model to use if available")
    
    args = parser.parse_args()
    
    services = args.services
    if not services:
        # If no services provided, try to find them (this requires kubernetes lib, 
        # but since we run in pod without it, we'll stick to manual list or error)
        print("Usage: python3 test-all-scouts.py scout-service1 scout-service2 ...")
        sys.exit(1)
    
    print(f"🔍 Cluster Mobile Scout Fleet Audit - Namespace: {namespace}")
    print(f"📋 Testing {len(services)} scout(s): {', '.join(services)}")
    
    results = {}
    for svc in services:
        results[svc] = test_inference(svc, args.model)
    
    print("\n" + "=" * 50)
    print("📊 FINAL AUDIT REPORT")
    print("=" * 50)
    success_count = sum(1 for r in results.values() if r)
    for svc, success in results.items():
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{svc:30} : {status}")
    print("=" * 50)
    print(f"Summary: {success_count}/{len(services)} active.")

if __name__ == "__main__":
    main()
