import socket, urllib.request
print('🌍 Testing egress to google.com...')
try:
    host = 'google.com'
    print(f'🔍 DNS Lookup for {host}...')
    # Use a low timeout for DNS if possible, but standard socket is fine
    ip = socket.gethostbyname(host)
    print(f'❌ Resolved {host} to {ip} (POLICY FAILURE!)')
except Exception as e:
    print(f'🛡️  NETWORK BLOCKED: {e}')
    print('✅ SUCCESS: The egress policy is working.')
