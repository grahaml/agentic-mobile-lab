"""Shared data model and alert thresholds — no heavy deps, safe to import on-device."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

# Alert thresholds — shared between collector.py (fleet) and device_dashboard.py (on-device)
ALERT_TEMP_C      = 42.0
ALERT_MEM_PCT     = 85.0
ALERT_BATTERY_PCT = 20
STALE_AFTER_S     = 120.0


@dataclass
class DeviceStatus:
    # Identity
    name: str
    ip: str
    base_url: str
    tier: str

    # Ollama
    ollama_ok: bool = False
    models_loaded: list[dict] = field(default_factory=list)
    models_available: list[str] = field(default_factory=list)

    # System metrics
    battery_pct: Optional[int] = None
    battery_temp_c: Optional[float] = None
    battery_status: Optional[str] = None
    mem_total_mb: Optional[int] = None
    mem_available_mb: Optional[int] = None
    swap_total_mb: Optional[int] = None
    swap_used_mb: Optional[int] = None
    cpu_temp_c: Optional[float] = None

    # Derived
    mem_used_pct: Optional[float] = None
    metrics_age_s: Optional[float] = None
    metrics_stale: bool = False
    alerts: list[str] = field(default_factory=list)
