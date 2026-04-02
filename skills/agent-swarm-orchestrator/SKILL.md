---
name: agent-swarm-orchestrator
description: Orchestrates specialized agentic workflows on the private cluster and mobile swarm. Use for security reviews, swarm health checks, and distributed code analysis.
---

# Agent Swarm Orchestrator

This skill provides specialized commands to interact with your private agent swarm and k3s cluster. It leverages native MCP tools provided by the Cluster Gateway.

## Slash Commands

### `/security-review`
Conducts a multi-vector security scan of your current code changes.
- **Trigger**: User wants a deep security audit of their work.
- **Workflow**:
    1.  Execute `git diff` to identify modified lines.
    2.  If the diff is too large (>4000 tokens), summarize the changes first.
    3.  Call the `mcp_agent_swarm_run_mvw_security_scan` tool, passing the diff content as the `code_snippet` argument.
    4.  Present the findings and the "Tech Lead" verdict from the mobile swarm.

### `/swarm-health`
Provides a real-time status report of the entire agent fleet.
- **Trigger**: User needs to verify if mobile nodes are online.
- **Workflow**:
    1.  Ping the Higress Gateway at `192.168.4.65` to confirm ingress health.
    2.  Check the status of cluster endpoints in the `agent-execution` namespace.
    3.  Report which physical devices (S20+, Motorola, etc.) are currently participating in the swarm.

## Usage Guidelines
- **High Complexity**: High-complexity analysis is routed by the cluster to the S20+ (Tech Lead). 
- **Latency**: Expect a 10-30 second delay for swarm-based tools as they utilize physical hardware.
- **Context Management**: This skill focuses on surgical context injection to avoid hitting mobile node RAM limits.
