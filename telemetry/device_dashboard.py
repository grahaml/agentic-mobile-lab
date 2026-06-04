"""On-device single-panel dashboard.

Reads ~/.last_metrics.json (written every 30s by metrics_push.sh) and renders
the same Rich panel used by the Macbuntu fleet dashboard — just for this device.

Usage (in Termux):
    python ~/telemetry/device_dashboard.py

Requires: rich  (pip install rich)
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import Optional

from rich.console import Console
from rich.live import Live
from rich.text import Text

# Reuse all rendering helpers from the fleet dashboard — single source of truth.
# The lazy import guard in dashboard.py means this works without pyyaml/receiver.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from telemetry.dashboard import _render_panel                              # noqa: E402
from telemetry.models import (                                             # noqa: E402
    DeviceStatus, STALE_AFTER_S, ALERT_TEMP_C, ALERT_MEM_PCT, ALERT_BATTERY_PCT,
)

METRICS_PATH = Path.home() / ".last_metrics.json"
DEVICE_INFO  = Path.home() / ".device-info"
INTERVAL     = 10  # seconds between refreshes


def _read_device_info() -> tuple[str, str]:
    """Return (name, role) from ~/.device-info, falling back to hostname."""
    name = role = ""
    if DEVICE_INFO.exists():
        for line in DEVICE_INFO.read_text().splitlines():
            if line.startswith("name="):
                name = line[5:]
            elif line.startswith("role="):
                role = line[5:]
    if not name:
        name = os.uname().nodename
    if not role:
        role = "unknown"
    return name, role


def _build_status(name: str, role: str) -> DeviceStatus:
    """Construct a DeviceStatus from the local metrics cache."""
    try:
        push = json.loads(METRICS_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        push = {}

    s = DeviceStatus(name=name, ip="localhost", base_url="", tier=role)

    s.battery_pct       = push.get("battery_pct")
    s.battery_temp_c    = push.get("battery_temp_c")
    s.battery_status    = push.get("battery_status")
    s.mem_total_mb      = push.get("mem_total_mb")
    s.mem_available_mb  = push.get("mem_available_mb")
    s.swap_total_mb     = push.get("swap_total_mb")
    s.swap_used_mb      = push.get("swap_used_mb")
    s.cpu_temp_c        = push.get("cpu_temp_c")

    ollama_ps = push.get("ollama_ps")
    if isinstance(ollama_ps, dict):
        s.ollama_ok      = True
        s.models_loaded  = list(ollama_ps.get("models", []) or [])

    ollama_tags = push.get("ollama_tags")
    if isinstance(ollama_tags, dict):
        s.models_available = [
            m.get("name", "") for m in (ollama_tags.get("models", []) or [])
        ]

    if s.mem_total_mb and s.mem_available_mb and s.mem_total_mb > 0:
        s.mem_used_pct = round(
            (1 - s.mem_available_mb / s.mem_total_mb) * 100, 1
        )

    # Staleness: compare file mtime against threshold
    if METRICS_PATH.exists():
        age = time.time() - METRICS_PATH.stat().st_mtime
        s.metrics_age_s  = age
        s.metrics_stale  = age > STALE_AFTER_S

    # Alerts (mirrors collector.py logic)
    alerts: list[str] = []
    if s.metrics_stale:
        alerts.append("stale")
    temp = s.battery_temp_c if s.battery_temp_c is not None else s.cpu_temp_c
    if temp is not None and temp >= ALERT_TEMP_C:
        alerts.append("high_temp")
    if s.battery_pct is not None and s.battery_pct <= ALERT_BATTERY_PCT \
            and s.battery_status == "discharging":
        alerts.append("low_battery")
    if s.mem_used_pct is not None and s.mem_used_pct >= ALERT_MEM_PCT:
        alerts.append("high_mem")
    if not s.ollama_ok and not s.metrics_stale and push:
        alerts.append("ollama_down")
    s.alerts = alerts

    return s


def main() -> None:
    name, role = _read_device_info()
    console = Console()

    with Live(console=console, refresh_per_second=1, screen=True) as live:
        while True:
            status = _build_status(name, role)
            live.update(_render_panel(status, width=console.width))
            time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
