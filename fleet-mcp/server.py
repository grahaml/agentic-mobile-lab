from mcp.server.fastmcp import FastMCP
import httpx
import logging
import asyncio

import os

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fleet-mcp")

# Initialize FastMCP
mcp = FastMCP("FleetMCP")

# Mobile Node Configuration (Environment driven for Cluster support)
S20_URL = os.getenv("S20_URL", "http://10.0.0.20:11434")
S10E_URL = os.getenv("S10E_URL", "http://10.0.0.10:11434")

NODES = {
    "s20": S20_URL,
    "s10e": S10E_URL
}

async def query_ollama(node_url: str, model: str, prompt: str):
    """Sends a raw prompt to Ollama with a strict 'shield' timeout."""
    url = f"{node_url}/api/generate"
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": False
    }
    
    logger.info(f"🛰️ Sending task to {node_url} (Model: {model})")
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(url, json=payload, timeout=300.0)
            response.raise_for_status()
            return response.json().get("response", "Error: No response from model.")
    except Exception as e:
        logger.error(f"❌ Error querying Ollama at {node_url}: {e}")
        return f"Error: {str(e)}"

@mcp.tool()
async def mobile_security_review(code_snippet: str) -> str:
    """
    Performs a security review of a code snippet using the S20 mobile node.
    Best for finding vulnerabilities and logic flaws in small snippets.
    """
    # The Shield: Construct a minimal, task-specific prompt
    prompt = (
        "You are a Senior Security Auditor. Analyze the following code for "
        "vulnerabilities, logic flaws, or security risks. Be concise and "
        "provide only actionable findings.\n\n"
        f"Code:\n{code_snippet}"
    )
    
    # Route to S20 (3B model)
    return await query_ollama(NODES["s20"], "qwen2.5-coder:3b", prompt)

@mcp.tool()
async def mobile_write_unit_test(code_snippet: str, language: str = "python") -> str:
    """
    Generates a unit test for a given code snippet using the S10e mobile node.
    Best for generating quick test coverage for functions.
    """
    # The Shield: Construct a minimal, task-specific prompt
    prompt = (
        f"Write a comprehensive unit test using a standard framework for the following {language} code. "
        "Return only the test code, no explanations.\n\n"
        f"Code:\n{code_snippet}"
    )
    
    # Route to S10e (1.5B model)
    return await query_ollama(NODES["s10e"], "qwen2.5-coder:1.5b", prompt)

# Expose as ASGI app
app = mcp.sse_app()

if __name__ == "__main__":
    mcp.run()
