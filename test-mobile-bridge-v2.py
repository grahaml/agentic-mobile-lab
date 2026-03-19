import urllib.request
import json
import socket
import os
import sys
import time

# Configuration
service_name = sys.argv[1] if len(sys.argv) > 1 else 'scout-sm-g970w'
model_name = sys.argv[2] if len(sys.argv) > 2 else 'qwen2.5:0.5b'
namespace = "agent-execution"

print(f'🔍 Starting Cluster-to-Mobile Swarm Test for {service_name}...')

# DNS and Environment Check
svc_dns = f'{service_name}.{namespace}.svc.cluster.local'
print(f"📡 Target DNS: {svc_dns}")

# Port scan check for Ollama (11434)
def check_port(host, port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(3)
        try:
            s.connect((host, port))
            return True
        except:
            return False

print(f"⏳ Pre-flight check: Verifying Port 11434 on {svc_dns}...")
if check_port(svc_dns, 11434):
    print("✅ Port 11434 is OPEN.")
else:
    print("❌ Port 11434 is CLOSED or UNREACHABLE.")
    # We continue anyway to see the specific error from urllib

url = f'http://{svc_dns}:11434/api/generate'

payload = json.dumps({
    'model': model_name,
    'prompt': 'Why is mobile computing the future of decentralized AI?',
    'stream': False
}).encode('utf-8')

req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})

try:
    print(f'🛰️  Calling Mobile Node via: {url} (Timeout: 120s)')
    start_time = time.time()
    with urllib.request.urlopen(req, timeout=120) as response:
        duration = time.time() - start_time
        if response.status == 200:
            result = json.loads(response.read().decode())
            response_text = result.get('response', 'No response field')
            print(f'\n✅ SUCCESS ({duration:.1f}s)! Mobile Node Responded:')
            print("-" * 40)
            print(response_text)
            print("-" * 40)
        else:
            print(f'❌ API Error {response.status}')
except Exception as e:
    print(f'❌ Network Error: {e}')
    print('\n💡 TROUBLESHOOTING:')
    print('1. Is "ollama serve" running on the phone?')
    print('2. Did you set OLLAMA_HOST=0.0.0.0 on the phone?')
    print('3. Is the phone on the same Wi-Fi as the cluster?')
