# Telemetry Spec 3: Collector (Push-Only Reader)

**Depends on:** Spec 1 (receiver) — imports `telemetry.receiver`
**Unblocks:** Spec 4 (dashboard consumes `DeviceStatus` objects produced here)
**Scope:** A pure data layer. One function — `collect_all()` — returns the current state of every device in the fleet by reading from `receiver.get_all()` and joining against the device config. **No network polling.** Every piece of device data comes from pushes that the device-side bash script (Spec 2) bundled together.

---

## Context for the agent

Every device pushes a coherent snapshot every 30 seconds: system metrics AND that device's own Ollama state (`/api/ps`, `/api/tags`) bundled into one POST. The receiver (Spec 1) stores the latest per device. Your job is to:

1. Read the device fleet from `telemetry/fleet.yaml` — that's still the single source of truth for what devices *should* exist.
2. Pull the latest pushed payload for each from `receiver.get_all()`.
3. Project those into `DeviceStatus` objects with derived fields, alerts, and staleness flags.

There is **no `requests` dependency, no `ThreadPoolExecutor`, no Ollama URLs to manage on Macbuntu.** If a device hasn't pushed recently, it's stale. If a device has never pushed, it's `never_seen`. If a device pushed but its `ollama_ps` field is `null`, the device is alive but Ollama is down.

---

## File to create

### `telemetry/collector.py`

**Required types and constants:**

```python
from dataclasses import dataclass, field
from typing import Optional, Callable

# Tunable at the top of the file
ALERT_TEMP_C      = 42.0   # battery_temp_c or cpu_temp_c above this → "high_temp"
ALERT_MEM_PCT     = 85.0   # mem_used_pct above this → "high_mem"
ALERT_BATTERY_PCT = 20     # battery_pct below this + discharging → "low_battery"
STALE_AFTER_S     = 90.0   # pushed metrics older than this → metrics_stale=True
TIER_ORDER        = ["high", "mid", "low", "ultra-low"]

@dataclass
class DeviceStatus:
    # Identity (from fleet.yaml)
    name: str
    ip: str                              # parsed from base_url
    base_url: str                        # e.g. "http://10.0.0.30:11434"
    tier: str                            # "high" | "mid" | "low" | "ultra-low"

    # Ollama (from the device's pushed payload — None if push lacked it)
    ollama_ok: bool = False              # True only if last push had non-null ollama_ps
    models_loaded: list[dict] = field(default_factory=list)   # ollama_ps["models"]
    models_available: list[str] = field(default_factory=list) # names from ollama_tags

    # System (from pushed payload; None if device never pushed)
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
    metrics_age_s: Optional[float] = None  # None if device has never pushed
    metrics_stale: bool = False            # True if last push older than STALE_AFTER_S
    alerts: list[str] = field(default_factory=list)
```

**Required exports:**

```python
def load_devices() -> list[dict]:
    """Reads telemetry/fleet.yaml, returns a flat de-duplicated
    list of {name, base_url, tier} dicts. If the same device name appears
    in multiple tiers, keep the highest-tier assignment (high > mid > low
    > ultra-low). Path is resolved relative to this file's parent's parent
    (so telemetry/collector.py finds fleet.yaml)."""

def collect_all() -> list[DeviceStatus]:
    """Joins fleet.yaml devices with receiver.get_all() pushes.
    Computes derived fields and alerts. Fires ALERT_HOOKS for each
    (device, alert) pair. Returns a list sorted by TIER_ORDER, then by name.
    Does NOT make any network calls."""
```

**Field mapping from push payload → DeviceStatus:**

| Push payload key | DeviceStatus field |
|---|---|
| `device` | (matched against `name`) |
| `battery_pct` | `battery_pct` |
| `battery_temp_c` | `battery_temp_c` |
| `battery_status` | `battery_status` |
| `mem_total_mb` | `mem_total_mb` |
| `mem_available_mb` | `mem_available_mb` |
| `swap_total_mb` | `swap_total_mb` |
| `swap_used_mb` | `swap_used_mb` |
| `cpu_temp_c` | `cpu_temp_c` |
| `ollama_ps` (object or null) | if non-null: `ollama_ok=True`, `models_loaded = ollama_ps.get("models", [])` |
| `ollama_tags` (object or null) | if non-null: `models_available = [m["name"] for m in ollama_tags.get("models", [])]` |
| `received_at` | drives `metrics_age_s` and `metrics_stale` |

**Derived field rules:**
- `mem_used_pct = (1 - mem_available_mb / mem_total_mb) * 100`, rounded to 1 decimal. None if either input is None.
- `metrics_age_s = time.time() - received_at` if a push exists, else None.
- `metrics_stale = metrics_age_s is not None and metrics_age_s > STALE_AFTER_S`.

**Alert rules:**
- `"high_temp"` if `(battery_temp_c or 0) >= ALERT_TEMP_C` or `(cpu_temp_c or 0) >= ALERT_TEMP_C`.
- `"high_mem"` if `mem_used_pct is not None and mem_used_pct >= ALERT_MEM_PCT`.
- `"low_battery"` if `battery_pct is not None and battery_status == "discharging" and battery_pct <= ALERT_BATTERY_PCT`.
- `"never_seen"` if the device is in fleet.yaml but `receiver.get_all()` has no entry for it. Suppresses all other alerts for that device (no data to alert on).
- `"stale"` if `metrics_stale` is True.
- `"ollama_down"` if a non-stale push exists but `ollama_ok` is False. Means "device alive, runtime not."

**Hooks:**

```python
ALERT_HOOKS: list[Callable[[DeviceStatus, str], None]] = []
```

For each device, after computing alerts, fire every hook for every alert. Wrap each call in try/except; on failure, log the exception to stderr but continue.

**Implementation notes:**

- IP extraction: `urllib.parse.urlparse(base_url).hostname`.
- Devices with unknown tiers sort to the end of the list.
- Receiver lookup is by device name: the `"device"` field in the push body must equal the device's `name` in `fleet.yaml`. If they don't match, the device will show as `never_seen` forever — call this out in a comment near `load_devices`.
- `collect_all()` should be cheap (just dict lookups and arithmetic). It's safe to call on every dashboard heartbeat.

---

## Verification

```bash
cd /home/grahaml/SideProjects/hermes-experimentation/telemetry
source .venv/bin/activate

# Sanity check the config reader:
python -c "from telemetry.collector import load_devices; import json; print(json.dumps(load_devices(), indent=2))"
# Expected: a flat list with moto, s20fe, s10e, ph1, s8 and their tiers.

# With no pushes — all devices should be 'never_seen':
python -c "
from telemetry import receiver, collector
receiver.start_background()
for d in collector.collect_all():
    print(f'{d.name:8} tier={d.tier:9} ollama_ok={d.ollama_ok}  alerts={d.alerts}')
"
# Expected: every device's alerts contains 'never_seen', ollama_ok=False.

# Fake a push with full Ollama data, confirm projection:
python -c "
import json, urllib.request, time
from telemetry import receiver, collector
receiver.start_background(); time.sleep(0.2)

payload = {
    'device': 's10e',
    'battery_pct': 74,
    'battery_temp_c': 38.5,
    'battery_status': 'discharging',
    'mem_total_mb': 6000,
    'mem_available_mb': 1800,
    'swap_total_mb': 4000,
    'swap_used_mb': 800,
    'cpu_temp_c': 41.0,
    'ollama_ps': {'models': [{'name': 'qwen2.5-coder:1.5b', 'expires_at': '2026-05-28T20:00:00Z'}]},
    'ollama_tags': {'models': [{'name': 'qwen2.5-coder:1.5b'}, {'name': 'qwen2.5:0.5b'}]},
}
req = urllib.request.Request('http://127.0.0.1:8765/metrics',
    data=json.dumps(payload).encode(),
    headers={'Content-Type': 'application/json'}, method='POST')
urllib.request.urlopen(req).read()

for d in collector.collect_all():
    if d.name == 's10e':
        print('ollama_ok:', d.ollama_ok)
        print('models_loaded:', [m['name'] for m in d.models_loaded])
        print('models_available:', d.models_available)
        print('mem_used_pct:', d.mem_used_pct)
        print('alerts:', d.alerts)
"
# Expected:
#   ollama_ok: True
#   models_loaded: ['qwen2.5-coder:1.5b']
#   models_available: ['qwen2.5-coder:1.5b', 'qwen2.5:0.5b']
#   mem_used_pct: 70.0
#   alerts: []   (or possibly empty — battery 74% is fine, temp under 42)
```

Stress an alert path — fake a push with Ollama null and old timestamp:

```bash
python -c "
import json, urllib.request, time
from telemetry import receiver, collector
receiver.start_background(); time.sleep(0.2)
urllib.request.urlopen(urllib.request.Request(
    'http://127.0.0.1:8765/metrics',
    data=json.dumps({'device': 's10e', 'battery_pct': 15, 'battery_status': 'discharging', 'ollama_ps': None, 'ollama_tags': None}).encode(),
    headers={'Content-Type': 'application/json'}, method='POST')).read()
for d in collector.collect_all():
    if d.name == 's10e': print(d.alerts)
"
# Expected: ['low_battery', 'ollama_down']
```

---

## Out of scope

- Any network polling — collector reads only from the receiver
- Any rendering / TUI / web — pure data layer
- Persistence (the receiver is in-memory; restarts wipe state)
- Acting on alerts beyond firing `ALERT_HOOKS` — actions live in caller code
