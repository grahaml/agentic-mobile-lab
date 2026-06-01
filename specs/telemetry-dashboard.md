# Plan: Hermes Fleet Telemetry Dashboard

## Context

The device fleet (5 phones + Macbuntu) has no observability. During inference runs we're blind — checking `curl /api/ps` manually, inferring activity from whether a phone is warm. This plan adds a proper telemetry layer: a data collector that polls every device on a heartbeat, a Rich TUI that surfaces it in real time, and a metric agent that runs in Termux on each Android node to expose system stats (RAM, temp, battery, swap) over HTTP.

Architecture is layered so the web UI can be bolted on later without changing the data layer.

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Macbuntu                                        │
│  ┌──────────────────────────────────────────┐   │
│  │  dashboard.py  (TUI, heartbeat loop)     │   │
│  │  collector.py  (polls Ollama API)        │   │
│  │  receiver.py   (receives metric pushes)  │   │
│  └──────────────────────────────────────────┘   │
│  :8765  POST /metrics  (push endpoint)           │
└────────────────▲─────────────────────────────────┘
                 │ HTTP POST on cron (every 30s)
     ┌───────────┴──────────────────────────────────┐
     │  each Android device (Termux)                │
     │                                              │
     │  metrics_push.sh  (bash, runs + exits)       │
     │  → termux-battery-status                     │
     │  → /proc/meminfo                             │
     │  → /proc/swaps                               │
     │  → /sys/class/thermal/*/temp                 │
     │  → curl POST → Macbuntu:8765/metrics         │
     │                                              │
     │  :11434  Ollama API  (polled from Macbuntu)  │
     └──────────────────────────────────────────────┘
```

**Two data sources per device:**
- **Ollama API** — polled from Macbuntu on each dashboard heartbeat. Already running, no setup needed. Provides: models loaded, model size, context length, expires_at (idle countdown), models available.
- **metrics_push.sh** — bash script on each device, scheduled via Termux cron (every 30s). Runs, collects, POSTs, exits. No resident process, zero memory overhead between runs.

---

## New Files

### `telemetry/`

```
telemetry/
├── requirements.txt     # rich, requests, pyyaml
├── collector.py         # polls Ollama API on all devices
├── receiver.py          # HTTP server on Macbuntu accepting metric pushes
├── dashboard.py         # Rich TUI, merges collector + receiver data
└── agent/
    ├── metrics_push.sh  # bash script for Termux — gather + POST + exit
    └── install.sh       # Termux setup: install curl, add to crontab
```

---

## `telemetry/requirements.txt`

```
rich>=13.0.0
requests
pyyaml
```

---

## `telemetry/collector.py`

Reads device list from `fleet.yaml` (single source of truth — extracts unique devices from tier pools). For each device, fires two requests concurrently (Ollama + metric agent) with short timeouts so an unreachable device doesn't block the rest.

**DeviceStatus dataclass:**
```python
@dataclass
class DeviceStatus:
    name: str
    ip: str
    tier: str
    # Ollama
    ollama_ok: bool
    models_loaded: list[dict]       # full /api/ps entries
    models_available: list[str]     # names from /api/tags
    # System (None if metric agent unreachable)
    battery_pct: int | None
    battery_temp_c: float | None
    battery_status: str | None      # "charging" | "discharging" | "full"
    mem_total_mb: int | None
    mem_available_mb: int | None
    swap_total_mb: int | None
    swap_used_mb: int | None
    # Derived
    mem_used_pct: float | None
    alerts: list[str]               # ["high_temp", "low_battery", "high_mem"]
```

**Alert thresholds (configurable at top of file):**
```python
ALERT_TEMP_C      = 42.0   # battery_temp_c above this
ALERT_MEM_PCT     = 85.0   # mem_used_pct above this
ALERT_BATTERY_PCT = 20     # battery_pct below this (and discharging)
OLLAMA_TIMEOUT    = 3      # seconds before marking device unreachable
METRIC_TIMEOUT    = 2
```

**collect_all() function:** Uses `concurrent.futures.ThreadPoolExecutor` to poll all devices in parallel. Returns `list[DeviceStatus]` sorted by tier (high → mid → low → ultra-low).

**Gemini bash scripts hook:** `metric_agent.py` calls `subprocess.run()` to execute any bash scripts for system data. This way Gemini's scripts drop straight in without changing the collector.

---

## `telemetry/agent/metrics_push.sh`

Bash script that runs in Termux, collects metrics, POSTs to Macbuntu, and exits. No persistent process.

```bash
#!/data/data/com.termux/files/usr/bin/bash
# Collect system metrics and push to Macbuntu collector.
# Designed to run via Termux cron every 30s.

COLLECTOR="http://10.0.0.1:8765/metrics"   # Macbuntu LAN IP
DEVICE_NAME="${DEVICE_NAME:-$(hostname)}"   # override via env if needed

# Battery (Termux API)
BATT=$(termux-battery-status 2>/dev/null)
BATT_PCT=$(echo "$BATT" | grep -o '"percentage":[0-9]*' | grep -o '[0-9]*')
BATT_TEMP=$(echo "$BATT" | grep -o '"temperature":[0-9.]*' | grep -o '[0-9.]*')
BATT_STATUS=$(echo "$BATT" | grep -o '"status":"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')

# Memory (/proc/meminfo — always available)
MEM_TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
MEM_AVAIL=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)

# Swap (/proc/swaps)
SWAP_TOTAL=$(awk 'NR==2 {print int($3/1024)}' /proc/swaps 2>/dev/null || echo 0)
SWAP_USED=$(awk 'NR==2 {print int($4/1024)}' /proc/swaps 2>/dev/null || echo 0)

# CPU temp (first readable thermal zone)
CPU_TEMP=""
for zone in /sys/class/thermal/thermal_zone*/temp; do
  val=$(cat "$zone" 2>/dev/null) && CPU_TEMP=$(echo "scale=1; $val/1000" | bc) && break
done

# Build JSON and POST
curl -s -X POST "$COLLECTOR" \
  -H "Content-Type: application/json" \
  -d "{
    \"device\": \"$DEVICE_NAME\",
    \"battery_pct\": ${BATT_PCT:-null},
    \"battery_temp_c\": ${BATT_TEMP:-null},
    \"battery_status\": \"${BATT_STATUS:-unknown}\",
    \"mem_total_mb\": ${MEM_TOTAL:-null},
    \"mem_available_mb\": ${MEM_AVAIL:-null},
    \"swap_total_mb\": ${SWAP_TOTAL:-0},
    \"swap_used_mb\": ${SWAP_USED:-0},
    \"cpu_temp_c\": ${CPU_TEMP:-null}
  }" &>/dev/null
```

The Macbuntu IP (`10.0.0.1`) needs to be set to the actual LAN address — or discovered via `ip route get 10.0.0.30 | awk '{print $NF; exit}'`.

---

## `telemetry/agent/install.sh`

```bash
#!/data/data/com.termux/files/usr/bin/bash
# Run once in Termux on each device to set up metric pushing.
# Requires: Termux:API app installed (for termux-battery-status)

MACBUNTU_IP="${1:?Usage: install.sh <macbuntu-ip>}"
DEVICE_NAME="${2:?Usage: install.sh <macbuntu-ip> <device-name>}"

# Patch the collector URL and device name into the script
sed -i "s|COLLECTOR=.*|COLLECTOR=\"http://$MACBUNTU_IP:8765/metrics\"|" metrics_push.sh
sed -i "s|DEVICE_NAME=.*|DEVICE_NAME=\"$DEVICE_NAME\"|" metrics_push.sh
chmod +x metrics_push.sh

# Add to Termux cron (every 30 seconds via two entries)
(crontab -l 2>/dev/null; echo "* * * * * $PWD/metrics_push.sh") | crontab -
(crontab -l 2>/dev/null; echo "* * * * * sleep 30 && $PWD/metrics_push.sh") | crontab -

echo "Installed. Pushing metrics to $MACBUNTU_IP every 30s as $DEVICE_NAME"
```

---

## `telemetry/receiver.py`

Tiny HTTP server on Macbuntu (port 8765). Accepts `POST /metrics` pushes from devices and stores the latest snapshot per device in memory with a timestamp. Thread-safe; runs in a background thread alongside the dashboard.

```python
# In-memory store (shared with dashboard via module-level dict)
_latest: dict[str, dict] = {}   # device_name → {metrics + "received_at"}

def get_all() -> dict[str, dict]:
    return dict(_latest)

def start_background(port=8765):
    # starts threading.Thread with http.server.HTTPServer
    ...
```

Dashboard calls `receiver.get_all()` on each refresh. If `received_at` is more than 90s ago, the metric data is considered stale and shown with a `?` indicator.

---

## `telemetry/dashboard.py`

Rich `Live` display, refreshes every 5 seconds (configurable via `--interval`).

**Layout:**
```
┌─ Hermes Fleet ──────────────── 5 devices · 2 active · 14:32:07 ─┐
│                                                                    │
│ ┌─ moto [HIGH] ──────────────┐  ┌─ s20fe [MID] ───────────────┐  │
│ │ ● qwen2.5-coder:7b-16k     │  │ ○ qwen2.5-coder:3b-16k      │  │
│ │   ctx 16k · expires 4m32s  │  │   idle                       │  │
│ │ Mem  ████████░░ 73% 5.1GB  │  │ Mem  ███░░░░░░░ 30% 1.8GB   │  │
│ │ Swap ██░░░░░░░░ 1.2GB used │  │ Swap ░░░░░░░░░░ 0            │  │
│ │ Temp 38°C  ▲ rising        │  │ Temp 28°C  — stable          │  │
│ │ Batt 74%  discharging      │  │ Batt 91%  charging           │  │
│ └────────────────────────────┘  └─────────────────────────────┘  │
│                                                                    │
│ ┌─ s10e [LOW] ───────────────┐  ┌─ ph1 [LOW] ────────────────┐   │
│ │ ○ idle                     │  │ ✗ unreachable               │   │
│ │ Mem  ██░░░░░░░░ 22%        │  │   Ollama not responding     │   │
│ │ Temp 25°C                  │  └─────────────────────────────┘   │
│ └────────────────────────────┘                                     │
└────────────────────────────────────────────────────────────────────┘
```

**Visual conventions:**
- `●` model active (loaded, request in flight or keepalive)
- `○` model idle / no model loaded
- `✗` device unreachable
- Alert badges in red: `[HIGH TEMP]` `[LOW BATT]` `[HIGH MEM]`
- Mem/swap bars colored: green < 70%, yellow 70–85%, red > 85%
- Temp colored: green < 38°C, yellow 38–42°C, red > 42°C

**CLI args:** `--interval N` (default 5), `--once` (single poll, no live refresh — useful for scripting/hooks)

---

## Hooks design

Alerts are just flags on `DeviceStatus.alerts` for now — the dashboard renders them visually. "Acting on them" is wired as a simple callback list:

```python
# in collector.py
ALERT_HOOKS: list[Callable[[DeviceStatus, str], None]] = []

# example hook (add to ALERT_HOOKS to enable):
def log_alert(device: DeviceStatus, alert: str):
    print(f"[{device.name}] ALERT: {alert}", file=sys.stderr)
```

Adding an action (e.g. unload model when temp > 42°C) = append a function to `ALERT_HOOKS`. The web UI phase can expose these as REST endpoints.

---

## Device list source

`collector.py` reads `fleet.yaml` and flattens all devices from all tiers into a `list[Device]`. This means adding a new device to `fleet.yaml` automatically appears in the dashboard — single source of truth.

---

## Web UI (later)

The same `collect_all()` call gets wrapped in a FastAPI endpoint `GET /api/status` → JSON. A single-page HTML file (no framework) polls it every 5s and renders the same data. No separate data layer work needed.

---

## Verification

1. Start dashboard on Macbuntu: `python dashboard.py` — devices show Ollama data, system metrics show `?` (no pushes yet)
2. On s10e: `bash install.sh <macbuntu-ip> s10e` — sets up cron, runs first push immediately
3. Within 30s, s10e panel on dashboard shows real battery/mem/temp data
4. Trigger an alert: run `graph.py` on Moto, watch temp badge appear as inference heats it up
5. Verify stale detection: stop cron on a device, after 90s the dashboard shows `?` on system metrics
6. `python dashboard.py --once` — single snapshot, exits; useful for scripting or hook testing
