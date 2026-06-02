"""Smoke test: verify ChatOllama can reach Remy's device before running the full graph."""
import os
from pathlib import Path

import yaml
from langchain_core.messages import HumanMessage
from langchain_ollama import ChatOllama

HERE = Path(__file__).parent

fleet_path = Path(os.environ.get(
    "FLEET_CONFIG",
    HERE.parent / "telemetry" / "fleet.yaml"))
with open(fleet_path) as f:
    config = yaml.safe_load(f)

device = config["tiers"]["mid"]["devices"][0]
print(f"Testing {device['name']} ({device['base_url']}) with {device['model']}...")

llm = ChatOllama(model=device["model"], base_url=device["base_url"])
response = llm.invoke([HumanMessage(content="Reply with exactly: wire test ok")])
print(f"Response: {response.content}")
