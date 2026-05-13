import json
import requests
import time
import re

def call_mcp_tool_sse(base_url, tool_name, arguments):
    """
    Calls an MCP tool over SSE transport and waits for the response on the SSE stream.
    """
    # 1. Connect to /sse to get the session ID
    print(f"🔗 Connecting to {base_url}/sse...")
    response = requests.get(f"{base_url}/sse", stream=True, timeout=60)
    
    session_endpoint = None
    stream_iterator = response.iter_lines()
    
    for line in stream_iterator:
        if line:
            line_str = line.decode("utf-8")
            if line_str.startswith("data: "):
                session_endpoint = line_str[6:].strip()
                break
    
    # 3. Wait for initialization (and session endpoint)
    print("⏳ Waiting for MCP initialization...")
    for line in stream_iterator:
        if line:
            line_str = line.decode("utf-8")
            if line_str.startswith("data: "):
                try:
                    data = json.loads(line_str[6:])
                    # Handle the session endpoint if not already found
                    if not session_endpoint and "endpoint" in line_str:
                         # Some implementations send it in a special format
                         pass
                    
                    if data.get("method") == "initialize":
                         # Respond to initialize if needed, but for simple clients we might just wait
                         print("⚙️  Received initialize request")
                         init_id = data.get("id")
                         # Send initialize response
                         init_payload = {
                             "jsonrpc": "2.0",
                             "id": init_id,
                             "result": {
                                 "protocolVersion": "2024-11-05",
                                 "capabilities": {},
                                 "serverInfo": {"name": "TestClient", "version": "1.0.0"}
                             }
                         }
                         requests.post(f"{base_url}{session_endpoint}", json=init_payload)
                         print("📤 Sent initialize response")
                    
                    if "result" in data and not session_endpoint:
                         # This might be the response to our init
                         pass
                         
                except:
                    # If it's just the raw endpoint string
                    if not session_endpoint:
                        session_endpoint = line_str[6:].strip()
                        print(f"✅ Session endpoint: {session_endpoint}")
                        # After getting endpoint, we should still wait for a bit or just proceed
                        break

    if not session_endpoint:
        return "Error: Could not find session endpoint"

    # 4. Call the tool
    msg_id = f"msg_{int(time.time() * 1000)}"
    payload = {
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {
            "name": tool_name,
            "arguments": arguments
        },
        "id": msg_id
    }
    
    if session_endpoint.startswith("/"):
        full_url = f"{base_url}{session_endpoint}"
    else:
        full_url = session_endpoint
        
    print(f"📡 Sending request to {full_url}...")
    resp = requests.post(full_url, json=payload, timeout=30)
    resp.raise_for_status()
    print(f"📥 Request accepted (status {resp.status_code})")
    
    # 3. Wait for the response in the SSE stream
    print("⏳ Waiting for tool response in SSE stream...")
    for line in stream_iterator:
        if line:
            line_str = line.decode("utf-8")
            if line_str.startswith("data: "):
                try:
                    data = json.loads(line_str[6:])
                    if data.get("id") == msg_id:
                        print("✅ Response received!")
                        tool_result = data.get("result", {}).get("content", [])
                        if tool_result:
                            return tool_result[0].get("text", "No text in result")
                        return "No content in tool response"
                except json.JSONDecodeError:
                    continue
                    
    return "Error: Stream closed before response was received"

if __name__ == "__main__":
    import sys
    code_path = "/home/grahaml/SideProjects/malicious_test.py"
    with open(code_path, "r") as f:
        code = f.read()
        
    # Using the LoadBalancer service directly on port 8001
    result = call_mcp_tool_sse("http://192.168.4.65:8001", "run_mvw_security_scan", {"code_snippet": code})
    print(f"\n### Swarm Security Review Result:\n\n{result}")
