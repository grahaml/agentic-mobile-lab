"""Telemetry collector — pure projection layer over the receiver.

Reads device pushes from `telemetry.receiver.get_all()` and joins them against
the device fleet declared in `telemetry/fleet.yaml`. Produces a
`DeviceStatus` per declared device with derived fields, staleness, and alerts.

NO network calls happen here. If a device hasn't pushed, it is `never_seen`.
If its last push lacks a non-null `ollama_ps`, Ollama is considered down on
that device. If its push is older than STALE_AFTER_S, it is `stale`.
"""

from __future__ import annotations

import sys
import time
import traceback
from pathlib import Path
from typing import Callable, Optional
from urllib.parse import urlparse

import yaml

from telemetry import receiver
from telemetry.models import DeviceStatus as _DeviceStatusBase

# Tunable thresholds
from telemetry.models import ALERT_TEMP_C, ALERT_MEM_PCT, ALERT_BATTERY_PCT, STALE_AFTER_S  # noqa: E402
TIER_ORDER = ["high", "mid", "low", "ultra-low"]

_TIER_RANK = {t: i for i, t in enumerate(TIER_ORDER)}


DeviceStatus = _DeviceStatusBase


# Hooks: called as hook(device_status, alert_name) for each fired alert.
# Failures are swallowed (logged to stderr) so one bad hook doesn't break
# collection for the rest of the fleet.
ALERT_HOOKS: list[Callable[["DeviceStatus", str], None]] = []


# fleet.yaml is the canonical device pool, kept right next to this module.
_CONFIG_PATH = Path(__file__).resolve().parent / "fleet.yaml"


def load_devices() -> list[dict]:
    """Read fleet.yaml and return a flat de-duplicated list of
    {name, base_url, tier} dicts.

    If the same device name appears in multiple tiers, the highest-tier
    assignment wins (high > mid > low > ultra-low).

    NOTE: the `name` here must match the `device` field that each device's
    push agent sends. A mismatch will leave the device permanently
    `never_seen` since the receiver keys pushes by that field.
    """
    with open(_CONFIG_PATH, "r") as f:
        config = yaml.safe_load(f) or {}

    tiers = config.get("tiers", {}) or {}
    # Walk tiers in priority order so the first seen entry wins.
    seen: dict[str, dict] = {}
    for tier_name in TIER_ORDER:
        tier_block = tiers.get(tier_name) or {}
        for dev in tier_block.get("devices", []) or []:
            name = dev.get("name")
            if not name or name in seen:
                continue
            seen[name] = {
                "name": name,
                "base_url": dev.get("base_url", ""),
                "tier": tier_name,
            }

    # Also pick up any tiers not in TIER_ORDER (defensive — shouldn't happen
    # in practice but keeps us from silently dropping config entries).
    for tier_name, tier_block in tiers.items():
        if tier_name in TIER_ORDER:
            continue
        for dev in (tier_block or {}).get("devices", []) or []:
            name = dev.get("name")
            if not name or name in seen:
                continue
            seen[name] = {
                "name": name,
                "base_url": dev.get("base_url", ""),
                "tier": tier_name,
            }

    return list(seen.values())


def _tier_sort_key(tier: str) -> int:
    # Unknown tiers sort to the end.
    return _TIER_RANK.get(tier, len(TIER_ORDER))


def _fire_hooks(status: DeviceStatus) -> None:
    for alert in status.alerts:
        for hook in ALERT_HOOKS:
            try:
                hook(status, alert)
            except Exception:
                sys.stderr.write(
                    f"collector: alert hook {hook!r} failed for "
                    f"{status.name}/{alert}:\n"
                )
                traceback.print_exc(file=sys.stderr)


def _project(device: dict, push: Optional[dict], now: float) -> DeviceStatus:
    base_url = device["base_url"]
    ip = urlparse(base_url).hostname or ""
    status = DeviceStatus(
        name=device["name"],
        ip=ip,
        base_url=base_url,
        tier=device["tier"],
    )

    if push is None:
        # Never pushed — only the never_seen alert applies; suppress others.
        status.alerts = ["never_seen"]
        return status

    # System metrics
    status.battery_pct = push.get("battery_pct")
    status.battery_temp_c = push.get("battery_temp_c")
    status.battery_status = push.get("battery_status")
    status.mem_total_mb = push.get("mem_total_mb")
    status.mem_available_mb = push.get("mem_available_mb")
    status.swap_total_mb = push.get("swap_total_mb")
    status.swap_used_mb = push.get("swap_used_mb")
    status.cpu_temp_c = push.get("cpu_temp_c")

    # Ollama
    ollama_ps = push.get("ollama_ps")
    if ollama_ps is not None:
        status.ollama_ok = True
        status.models_loaded = list(ollama_ps.get("models", []) or [])

    ollama_tags = push.get("ollama_tags")
    if ollama_tags is not None:
        status.models_available = [
            m.get("name", "") for m in (ollama_tags.get("models", []) or [])
        ]

    # Derived: mem_used_pct
    if (
        status.mem_total_mb is not None
        and status.mem_available_mb is not None
        and status.mem_total_mb > 0
    ):
        status.mem_used_pct = round(
            (1 - status.mem_available_mb / status.mem_total_mb) * 100, 1
        )

    # Derived: staleness
    received_at = push.get("received_at")
    if isinstance(received_at, (int, float)):
        status.metrics_age_s = now - received_at
        status.metrics_stale = status.metrics_age_s > STALE_AFTER_S

    # Alerts
    alerts: list[str] = []

    if status.metrics_stale:
        alerts.append("stale")

    # high_temp: either battery or cpu over threshold
    bt = status.battery_temp_c or 0
    ct = status.cpu_temp_c or 0
    if bt >= ALERT_TEMP_C or ct >= ALERT_TEMP_C:
        alerts.append("high_temp")

    if status.mem_used_pct is not None and status.mem_used_pct >= ALERT_MEM_PCT:
        alerts.append("high_mem")

    if (
        status.battery_pct is not None
        and status.battery_status == "discharging"
        and status.battery_pct <= ALERT_BATTERY_PCT
    ):
        alerts.append("low_battery")

    # ollama_down fires only when the push is fresh — if the push is stale
    # we don't really know whether Ollama is down or the whole device fell
    # off the network. `stale` already covers that case.
    if not status.metrics_stale and not status.ollama_ok:
        alerts.append("ollama_down")

    status.alerts = alerts
    return status


def collect_all() -> list[DeviceStatus]:
    """Project the current fleet state from receiver pushes + device config.

    Cheap: a few dict lookups and arithmetic per device. Safe to call on
    every dashboard heartbeat. Fires ALERT_HOOKS for each (device, alert)
    pair after building the status. Returns the list sorted by tier
    (per TIER_ORDER) then by name.
    """
    devices = load_devices()
    pushes = receiver.get_all()
    now = time.time()

    statuses = [_project(dev, pushes.get(dev["name"]), now) for dev in devices]
    statuses.sort(key=lambda s: (_tier_sort_key(s.tier), s.name))

    for status in statuses:
        _fire_hooks(status)

    return statuses
