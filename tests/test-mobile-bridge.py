import urllib.request
import json
import socket
import os
import sys

# Get service name from argument or default to mobile-scout
service_name = sys.argv[1] if len(sys.argv) > 1 else 'mobile-scout'
env_prefix = service_name.upper().replace('-', '_')

print(f'🔍 Starting Cluster-to-Mobile Swarm Test for {service_name}...')

# Kubernetes automatically injects environment variables for services in the same namespace.
svc_host = os.environ.get(f'{env_prefix}_SERVICE_HOST')
svc_port = os.environ.get(f'{env_prefix}_SERVICE_PORT_OLLAMA') or '11434'

if not svc_host:
    print(f"⚠️  {env_prefix}_SERVICE_HOST not found.")
    print(f"Falling back to DNS name: {service_name}.agent-execution.svc.cluster.local")
    svc_host = f'{service_name}.agent-execution.svc.cluster.local'

url = f'http://{svc_host}:{svc_port}/api/generate'

payload = json.dumps({
    'model': 'qwen2.5-coder:1.5b',
    'prompt': 'Please tell me a short story about code.',
    'stream': False
}).encode('utf-8')

req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json'})

try:
    print(f'🛰️  Calling Mobile Node via: {url} (Timeout: 300s)')
    with urllib.request.urlopen(req, timeout=300) as response:
        if response.status == 200:
            result = json.loads(response.read().decode())
            response_text = result.get('response', 'No response field')
            print(f'✅ SUCCESS! Mobile Node Responded: {response_text}')
        else:
            print(f'❌ API Error {response.status}')
except socket.timeout:
    print('❌ Timeout: Mobile Node did not respond in time.')
except Exception as e:
    print(f'❌ Network Error: {e}')
    print('💡 Check if Ollama is running with OLLAMA_HOST=0.0.0.0 on the phone.')
