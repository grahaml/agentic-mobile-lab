# Telemetry Spec 4: Rich TUI Dashboard

**Depends on:** Spec 1 (receiver), Spec 3 (collector) — both must be implemented
**Unblocks:** future web UI (Spec 5, not yet written) — but that work just wraps `collector.collect_all()` and doesn't change anything you do here
**Scope:** A terminal UI that polls `collect_all()` on a heartbeat and renders a grid of device panels with live model status, memory, swap, temperature, battery, and alert badges.

---

## Context for the agent

You're the visible end of the pipeline. The data layer is done — `telemetry.collector.collect_all()` returns a sorted `list[DeviceStatus]` on demand. Your job is to call it every N seconds and render a Rich live-updating TUI.

Two run modes:
- **Live mode (default):** `python dashboard.py` — refreshes every 5 seconds using `rich.live.Live`, runs until Ctrl-C.
- **One-shot mode:** `python dashboard.py --once` — prints a single snapshot and exits 0. Useful for cron-style sanity checks and scripting hooks.

The receiver must be running for system metrics to show up. Start it in a background thread inside the dashboard process via `receiver.start_background()` — no separate process needed.

---

## File to create

### `telemetry/dashboard.py`

**CLI:**

```
python dashboard.py [--interval SECONDS] [--once] [--port PORT]

  --interval N   Refresh interval in live mode. Default: 5
  --once         Print one snapshot and exit. No live display.
  --port PORT    Receiver port. Default: 8765
```

**Boot sequence:**

1. Parse args.
2. Call `receiver.start_background(port=args.port)`.
3. If `--once`: render one snapshot to the terminal, exit 0.
4. Otherwise: enter `rich.live.Live` loop, re-render every `args.interval` seconds. Catch `KeyboardInterrupt` to exit cleanly.

**Layout:**

Top-level: a `rich.layout.Layout` (or simpler `rich.console.Group`) with:
- A header line: `Hermes Fleet · N devices · K active · <HH:MM:SS>` where K is the count of devices with at least one model loaded.
- A grid of panels — one per device — using `rich.columns.Columns` so they flow into 2 or 3 columns automatically based on terminal width.
- Panels sorted in the same order `collect_all()` returns (high tier first).

**Panel content (per device):**

```
┌─ moto [HIGH] ───────────────────[HIGH TEMP]─┐
│ ● qwen2.5-coder:7b-16k                       │
│   ctx 16384 · expires in 4m32s               │
│ Mem  ████████░░ 73%  5.1 / 7.0 GB            │
│ Swap ██░░░░░░░░ 1.2 / 5.0 GB                 │
│ Temp 38.5°C  battery                         │
│ Batt 74%  discharging                        │
└──────────────────────────────────────────────┘
```

**Symbol conventions:**
- First char: `●` if `models_loaded` is non-empty, `○` if loaded list is empty but `ollama_ok`, `✗` if not `ollama_ok`.
- Model line: show the first loaded model's name and a derived `expires in Xm Ys` from its `expires_at` (parse the RFC 3339 timestamp; if the timestamp is in the past, show `idle`). If multiple models loaded, show first and append ` (+N more)`.
- Idle device: omit the model lines, render `idle` after the `○`.
- Unreachable device: omit mem/swap/temp/batt lines, render `Ollama unreachable` below the title.

**Coloring:**
- Mem bar: green `mem_used_pct < 70`, yellow `70 ≤ x < 85`, red `≥ 85`. Use `rich`'s `[green]` `[yellow]` `[red]` styles.
- Swap bar: yellow if `swap_used_mb > 0`, red if it's more than half of `swap_total_mb`. No swap usage → grey.
- Temp: green `< 38`, yellow `38–42`, red `≥ 42`. Color applies to both number and unit.
- Battery: green `≥ 50`, yellow `20–49`, red `< 20`. Status string in dim style.

**Alert badges:**
- Render at the right side of the panel title in red, e.g. `[HIGH TEMP]`, `[LOW BATT]`, `[HIGH MEM]`, `[STALE]`.
- Map from `DeviceStatus.alerts` strings: `"high_temp"` → `HIGH TEMP`, etc.
- Multiple badges concatenate with spaces.

**Stale metrics:**
- If `metrics_stale` is True, render system fields in `dim` style and add the `[STALE]` badge. Still show the values (they're the last-known).
- If a system field is `None`, render `—` in its place. No bar.

**Bar rendering helper:**
Implement a small `_bar(used_pct: float, width: int = 10) -> str` that returns a unicode bar with `█` (filled) and `░` (empty). Used for mem and swap.

**Expiry timestamp parsing:**
Ollama returns `expires_at` like `"2026-05-28T15:35:00.488777399-04:00"`. Use `datetime.fromisoformat()` (Python 3.11+ tolerates the timezone). Compute `(expires - now).total_seconds()` and format as `Xm Ys` (e.g. `4m 32s`), or `idle` if negative.

---

## Verification

Smoke test in `--once` mode (no need for any real devices):

```bash
cd /home/grahaml/SideProjects/hermes-experimentation/telemetry
source .venv/bin/activate
python dashboard.py --once
```

Expected: a single panel grid prints, devices that are unreachable show `✗ Ollama unreachable`, reachable devices show their current state, system fields are `—` until pushes arrive.

Live test:

```bash
python dashboard.py --interval 3
```

Watch the header time update every 3 seconds. Ctrl-C should exit cleanly with no traceback.

End-to-end visual check (requires Spec 2 to be running on at least one phone, plus an active inference task to load a model):

1. Start the dashboard.
2. From another shell, kick off `langgraph/graph.py` so Remy loads on s20fe and a specialist loads on its device.
3. The dashboard should show `●` light up on the active device, the model name, and a decreasing `expires in ...` countdown.

---

## Out of scope

- The web UI (separate spec, later)
- Acting on alerts (the collector exposes `ALERT_HOOKS` for that — caller code, not dashboard code)
- Historical graphs / sparklines (single snapshot per refresh is enough for now)
- Configurable layouts — fixed 2/3 column responsive grid
