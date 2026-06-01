# Telemetry Spec 1: Scaffold + Push Receiver

**Depends on:** nothing
**Unblocks:** Spec 2 (devices need a receiver to push to)
**Scope:** Macbuntu side. Set up `telemetry/` directory, dependencies, and the HTTP endpoint that accepts metric pushes from devices.

---

## Context for the agent

You are creating the receiving end of a push-based telemetry pipeline. Android devices on the LAN will POST their system metrics to a small HTTP server on Macbuntu (port 8765). Your job is to scaffold the project and write that receiver.

You do NOT need to touch devices, Ollama APIs, or build any UI in this spec — only the receiver and the project skeleton.

---

## Files to create

### `telemetry/requirements.txt`

```
rich>=13.0.0
requests
pyyaml
```

### `telemetry/.gitignore`

```
.venv/
__pycache__/
*.pyc
```

### `telemetry/receiver.py`

In-process HTTP server using `http.server.BaseHTTPRequestHandler`. Runs in a background thread so the dashboard can call into it directly via `get_all()`. State is a module-level dict guarded by a `threading.Lock`.

**Required exports:**

```python
def get_all() -> dict[str, dict]:
    """Returns a snapshot of the latest push from each device.
    Keys are device names; values are the JSON body that was POSTed
    plus a 'received_at' float (time.time() at receipt)."""

def start_background(port: int = 8765) -> None:
    """Starts the receiver in a daemon thread. Idempotent — calling
    twice is a no-op (second call returns immediately)."""
```

**Behavior:**
- `POST /metrics` — parse JSON body, require a `"device"` field (str). Store under that key in the internal dict with `received_at = time.time()`. Return `204 No Content`.
- `POST /metrics` with malformed body or missing `device` field — return `400 Bad Request`.
- Any other method/path — return `404`.
- Log errors to stderr, never to stdout (stdout belongs to the dashboard).

**Concurrency:** Use `socketserver.ThreadingMixIn` with `HTTPServer` so multiple pushes can land at once without queueing.

### `telemetry/__init__.py`

Empty file (makes `telemetry` an importable package).

---

## Verification

From `telemetry/`:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Smoke test the receiver:
python -c "
import time, json, urllib.request
from telemetry import receiver
receiver.start_background(8765)
time.sleep(0.2)
req = urllib.request.Request(
    'http://127.0.0.1:8765/metrics',
    data=json.dumps({'device': 'test', 'mem_total_mb': 7000}).encode(),
    headers={'Content-Type': 'application/json'},
    method='POST',
)
urllib.request.urlopen(req).read()
print(receiver.get_all())
"
```

Expected: `{'test': {'device': 'test', 'mem_total_mb': 7000, 'received_at': <float>}}`

Also test the 400 path:
```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8765/metrics -d 'not json'
# expected: 400
```

---

## Out of scope (don't do this)

- Persistence — in-memory only, restarts wipe state
- Authentication — LAN-only, no auth needed
- Rate limiting
- TLS
- The dashboard, collector, or any device-side scripts
