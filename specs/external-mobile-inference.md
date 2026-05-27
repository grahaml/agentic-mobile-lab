---
title: External Mobile Inference Architecture
date: 2026-05-27
status: Active
---

# External Mobile Inference Architecture

## Decision

Mobile nodes are **NOT** bridged into the k3s cluster. Instead, they operate as independent network services on the private 10.0.0.0/24 network, directly accessible from cluster pods.

## Why Not Bridge?

**Previous approach (k8s service bridging):**
- Mobile nodes registered as k8s Services/Endpoints
- Pods discover nodes via DNS (`mobile-scout-s20`, etc.)
- MCP server or agents call k8s services
- Added complexity: SSH tunnels, k8s manifests, service discovery

**Current approach (direct network):**
- Mobile nodes are static on 10.0.0.0/24 with known IPs
- Pods reach them directly via HTTP (Ollama API) or SSH
- No k8s abstraction layer needed
- Simpler: fewer moving parts, easier debugging

**Trade-offs:**
| Aspect | Bridged | Direct |
|--------|---------|--------|
| Complexity | Higher | Lower ✅ |
| Discovery | k8s DNS | Static IPs ✅ |
| Routing | Service abstraction | Direct HTTP ✅ |
| Debugging | k8s logs + SSH | Network trace ✅ |
| Scaling | Add service + endpoint | Add static IP ✅ |

## Current State

**Control Plane:**
- Macbuntu host running k3s cluster
- `agent-execution` namespace ready for Hermes agents
- Kubeconfig at `~/.kube/k3s-config`

**Inference Nodes:**
- **Moto2023** (10.0.0.30): Ollama running, qwen2.5-coder:1.5b loaded
  - Accessible at: `http://10.0.0.30:11434`
  - SSH: `u0_a388@10.0.0.30:8022`
- **S10e** (10.0.0.10): Provisioned, ready for models
- **S20 FE** (10.0.0.20): Provisioned, ready for models

## Architecture Diagram

```
┌─────────────────────────────────────────────────┐
│         Macbuntu Host (k3s Cluster)             │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │   agent-execution namespace               │ │
│  │                                           │ │
│  │  ┌──────────┐  ┌──────────┐  ┌────────┐ │ │
│  │  │  Remy    │  │ Taran    │  │ MCP    │ │ │
│  │  │  (Pod)   │  │ (Pod)    │  │Broker  │ │ │
│  │  └──────────┘  └──────────┘  └────────┘ │ │
│  └───────────────────────────────────────────┘ │
│                      │                         │
│  ┌──────────────────┼────────────────────────┐ │
│  │ Network (host access to 10.0.0.0/24)      │ │
│  └──────────────────┼────────────────────────┘ │
└─────────────────────┼──────────────────────────┘
                      │
         ┌────────────┼────────────┐
         │            │            │
    ┌────▼────┐  ┌────▼────┐ ┌────▼────┐
    │  Moto   │  │   S10e  │ │ S20 FE  │
    │  2023   │  │         │ │         │
    │ :11434  │  │ (ready) │ │(ready)  │
    └─────────┘  └─────────┘ └─────────┘
```

## How Agents Call Ollama

**Option A: Direct HTTP (Recommended)**
```python
# Agent code running in k3s pod
import requests
response = requests.post(
    "http://10.0.0.30:11434/api/generate",
    json={"model": "qwen2.5-coder:7b", "prompt": "..."}
)
```

**Option B: SSH + Local CLI (If needed for advanced features)**
```bash
# From agent pod
ssh -i /path/to/key u0_a388@10.0.0.30 \
  "chroot /data/local/ubuntu /bin/su - agent-lab -c 'ollama run qwen2.5-coder:7b \"...\"'"
```

## Next Steps

1. **Pull larger models to Moto2023**
   - Test: qwen2.5-coder:7b, mistral:7b
   - Verify RAM/inference performance

2. **Deploy Hermes vertical slice**
   - Remy + Taran agents as pods
   - Wire HTTP calls to 10.0.0.30:11434

3. **Test end-to-end**
   - Ask Remy a complex question
   - Verify decomposition → Taran → Moto2023 → response

4. **Expand inference**
   - Load different models on S10e, S20 FE
   - Implement specialist → node routing (e.g., quick tasks → Moto, complex → S10e if needed)

## Model Inventory

**Moto2023 (10.0.0.30) — Primary Inference Node**
- Currently: qwen2.5-coder:1.5b (986MB)
- Candidates: qwen2.5-coder:7b, mistral:7b
- Disk space: Sufficient for 2-3 models at 7B+ scale

**S10e (10.0.0.10) — Secondary (TBD)**
- Role: TBD (monitoring, lightweight tasks, fallback)

**S20 FE (10.0.0.20) — Secondary (TBD)**
- Role: TBD (monitoring, lightweight tasks, fallback)

## Future: Hybrid Inference

Once working locally, consider:
- **Simple tasks** (decomposition, routing) → Moto2023 (fast, local)
- **Complex tasks** (code review, design) → Anthropic Claude (higher capability)
- **Fallback** → Anthropic if Moto2023 is busy/offline

This keeps latency low for most work while preserving high-capability responses when needed.
