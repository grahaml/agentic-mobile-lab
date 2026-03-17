import urllib.request
import json
import socket
import os

print('🔍 Starting Cluster-to-Mobile Swarm Test (Dynamic Discovery)...')

# Kubernetes automatically injects environment variables for services in the same namespace.
# For the 'mobile-scout' service, these will be available:
svc_host = os.environ.get('MOBILE_SCOUT_SERVICE_HOST')
svc_port = os.environ.get('MOBILE_SCOUT_SERVICE_PORT_OLLAMA') or '11434'

if not svc_host:
    print("⚠️  MOBILE_SCOUT_SERVICE_HOST not found. (Are we running inside the cluster?)")
    print("Falling back to DNS name...")
    svc_host = 'mobile-scout.agent-execution.svc.cluster.local'

url = f'http://{svc_host}:{svc_port}/api/generate'

payload = json.dumps({
    'model': 'qwen2.5-coder:1.5b',
    'prompt': 'hi',
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
