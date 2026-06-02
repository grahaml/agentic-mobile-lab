"""Step 3b: LangGraph multi-agent vertical slice — Remy + Taran.

Routing logic lives in Python (route_decision), not in the model.
Remy generates a JSON routing block; extract_route parses it; the graph
edges decide which node fires next. No function-calling protocol required.
"""
import json
import os
import random
import re
from pathlib import Path
from typing import TypedDict

import yaml
from dotenv import load_dotenv
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_ollama import ChatOllama
from langgraph.graph import END, StateGraph

load_dotenv()

HERE = Path(__file__).parent
SOULS = HERE / "souls"

ROUTING_INSTRUCTION = """
After your analysis, end your response with a routing block in this exact format:
```json
{"route": "<specialist>", "brief": "<clear task description for the specialist>"}
```
Specialist options: taran, sable, soren, iris, jules, pria, kai
Use "none" as the route if you can answer the task directly without a specialist.
"""

VALID_ROUTES = {"taran", "sable", "soren", "iris", "jules", "pria", "kai"}


# ---------------------------------------------------------------------------
# Config helpers (carried over from crewai/crew.py)
# ---------------------------------------------------------------------------

FLEET_CONFIG = Path(os.environ.get(
    "FLEET_CONFIG",
    HERE.parent / "telemetry" / "fleet.yaml"))


def load_config():
    with open(HERE / "persona_config.yaml") as f:
        config = yaml.safe_load(f)
    with open(FLEET_CONFIG) as f:
        config["tiers"] = yaml.safe_load(f)["tiers"]
    return config


def pick_device(tier_name, config):
    # TODO: add per-device semaphore when moving to parallel graph execution
    devices = config["tiers"][tier_name]["devices"]
    return random.choice(devices)


def build_chat_model(persona_name, config):
    tier = config["personas"][persona_name]["tier"]
    device = pick_device(tier, config)
    return ChatOllama(model=device["model"], base_url=device["base_url"])


def load_soul(filename):
    return (SOULS / filename).read_text()


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

class AgentState(TypedDict):
    task: str               # original user input
    remy_response: str      # Remy's full text output
    route: str              # parsed routing decision
    brief: str              # extracted task for the specialist
    specialist_output: str  # specialist's final output


# ---------------------------------------------------------------------------
# Routing helper
# ---------------------------------------------------------------------------

def extract_route(text: str) -> tuple[str, str]:
    """Extract route and brief from Remy's response.
    Tries in order: fenced ```json block, whole-text JSON, greedy brace scan.
    Returns ("none", text) if nothing parseable is found."""
    candidates = []

    # 1. Prefer fenced block
    fenced = re.search(r"```json\s*(\{.*\})\s*```", text, re.DOTALL)
    if fenced:
        candidates.append(fenced.group(1))

    # 2. Whole text may be bare JSON (Remy sometimes outputs nothing else)
    candidates.append(text.strip())

    # 3. Greedy brace scan for embedded JSON objects
    for m in re.finditer(r"\{.*\}", text, re.DOTALL):
        candidates.append(m.group(0))

    for raw in candidates:
        try:
            data = json.loads(raw)
            if isinstance(data, dict):
                route = data.get("route", "none")
                brief = data.get("brief", text)
                if route in VALID_ROUTES:
                    return route, brief
        except json.JSONDecodeError:
            pass

    return "none", text


# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------

config = load_config()


def remy_node(state: AgentState) -> dict:
    llm = build_chat_model("remy", config)
    soul = load_soul(config["personas"]["remy"]["soul"])
    messages = [
        SystemMessage(content=soul + ROUTING_INSTRUCTION),
        HumanMessage(content=state["task"]),
    ]
    response = llm.invoke(messages)
    route, brief = extract_route(response.content)
    return {
        "remy_response": response.content,
        "route": route,
        "brief": brief,
    }


def taran_node(state: AgentState) -> dict:
    llm = build_chat_model("taran", config)
    soul = load_soul(config["personas"]["taran"]["soul"])
    messages = [
        SystemMessage(content=soul),
        HumanMessage(content=state["brief"]),
    ]
    response = llm.invoke(messages)
    return {"specialist_output": response.content}


def soren_node(state: AgentState) -> dict:
    llm = build_chat_model("soren", config)
    soul = load_soul(config["personas"]["soren"]["soul"])
    messages = [
        SystemMessage(content=soul),
        HumanMessage(content=state["brief"]),
    ]
    response = llm.invoke(messages)
    return {"specialist_output": response.content}


def pria_node(state: AgentState) -> dict:
    llm = build_chat_model("pria", config)
    soul = load_soul(config["personas"]["pria"]["soul"])
    messages = [
        SystemMessage(content=soul),
        HumanMessage(content=state["brief"]),
    ]
    response = llm.invoke(messages)
    return {"specialist_output": response.content}


def jules_node(state: AgentState) -> dict:
    llm = build_chat_model("jules", config)
    soul = load_soul(config["personas"]["jules"]["soul"])
    messages = [
        SystemMessage(content=soul),
        HumanMessage(content=state["brief"]),
    ]
    response = llm.invoke(messages)
    return {"specialist_output": response.content}


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

def route_decision(state: AgentState) -> str:
    route = state.get("route", "none")
    if route in ("taran", "sable"):
        return "taran"
    if route == "soren":
        return "soren"
    if route == "pria":
        return "pria"
    if route in ("jules", "iris"):
        return "jules"
    # kai, voss, and any unknown valid routes fall through to taran for now
    if route in VALID_ROUTES:
        return "taran"
    return END


# ---------------------------------------------------------------------------
# Graph
# ---------------------------------------------------------------------------

builder = StateGraph(AgentState)
builder.add_node("remy", remy_node)
builder.add_node("taran", taran_node)
builder.add_node("soren", soren_node)
builder.add_node("pria", pria_node)
builder.add_node("jules", jules_node)
builder.set_entry_point("remy")
builder.add_conditional_edges(
    "remy",
    route_decision,
    {"taran": "taran", "soren": "soren", "pria": "pria", "jules": "jules", END: END},
)
builder.add_edge("taran", END)
builder.add_edge("soren", END)
builder.add_edge("pria", END)
builder.add_edge("jules", END)
graph = builder.compile()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse
    import sys

    parser = argparse.ArgumentParser()
    parser.add_argument("--task", default=(
        "A new product idea has come in: a basic task tracker "
        "(think very simple Todoist). We need a first-cut REST API design."
    ))
    args = parser.parse_args()

    initial_state: AgentState = {
        "task": args.task,
        "remy_response": "",
        "route": "",
        "brief": "",
        "specialist_output": "",
    }

    print(f"Task:   {args.task[:100]}...", flush=True)
    print("Running graph...", flush=True)

    # stream(mode="values") yields full state after each node completes
    result = None
    for state in graph.stream(initial_state, stream_mode="values"):
        result = state
        # print whichever fields just got populated
        if state.get("route") and not state.get("specialist_output"):
            print(f"\n[remy] done — route → {state['route']}", flush=True)
            print(f"  brief → {state['brief'][:100]}...", flush=True)
        elif state.get("specialist_output"):
            print(f"\n[{state['route']}] done", flush=True)

    print(f"\nRoute:  {result['route']}")
    print(f"Brief:  {result['brief'][:120]}...")
    print("\n" + "=" * 60)
    print("FINAL OUTPUT")
    print("=" * 60)
    print(result["specialist_output"] or result["remy_response"])
