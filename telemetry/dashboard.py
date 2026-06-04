"""Telemetry dashboard — Rich TUI over `collector.collect_all()`.

Runs the push receiver in a background daemon thread, then polls the
collector on a heartbeat and renders a responsive grid of device panels.

Two modes:
  --once       Print a single snapshot to the terminal and exit 0.
  (default)    Live-update every --interval seconds until Ctrl-C.

Layout: a header line summarising the fleet, then a flow of one panel per
device via `rich.columns.Columns` (auto 2/3 column responsive). Panels are
rendered in the order `collect_all()` returns (high → mid → low → ultra-low
then by name) — we don't re-sort here.
"""

from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# Allow `python telemetry/dashboard.py` as well as `python -m telemetry.dashboard`
# by putting the repo root on sys.path when invoked as a top-level script.
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from rich.columns import Columns
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.text import Text

# collector and receiver are only needed in fleet mode (not --local).
# Import them lazily so device_dashboard.py can import rendering helpers
# from this module without pulling in pyyaml or the HTTP receiver.
try:
    from telemetry import collector, receiver
    from telemetry.collector import DeviceStatus
except ImportError:
    collector = None  # type: ignore[assignment]
    receiver = None   # type: ignore[assignment]
    from telemetry.models import DeviceStatus  # type: ignore[no-redef]


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def _bar(used_pct: float, width: int = 10) -> str:
    """Unicode bar: `█` filled, `░` empty. Clamped to [0, 100]."""
    pct = max(0.0, min(100.0, used_pct))
    filled = int(round((pct / 100.0) * width))
    filled = max(0, min(width, filled))
    return "█" * filled + "░" * (width - filled)


# Offset from ASCII printable range (0x21–0x7E) to fullwidth range (0xFF01–0xFF5E).
_FW_OFFSET = ord("！") - ord("!")


def _fw(s: str) -> str:
    """Return s with ASCII printable chars replaced by their fullwidth equivalents.

    Fullwidth chars occupy 2 terminal columns, making labels and numbers visibly
    larger on high-DPI phone screens without changing font settings.
    Spaces and non-ASCII chars (°, GB suffixes) are passed through unchanged.
    """
    return "".join(
        chr(ord(c) + _FW_OFFSET) if "!" <= c <= "~" else c
        for c in s
    )


def _format_expires_at(expires_at: Optional[str]) -> str:
    """Format Ollama's RFC 3339 `expires_at` as `Xm Ys`, or `idle` if past."""
    if not expires_at or not isinstance(expires_at, str):
        return "idle"
    try:
        # Python 3.11+ tolerates the trailing offset like -04:00 directly.
        expires = datetime.fromisoformat(expires_at)
    except ValueError:
        return "idle"

    now = datetime.now(expires.tzinfo) if expires.tzinfo else datetime.now()
    remaining = (expires - now).total_seconds()
    if remaining <= 0:
        return "idle"
    # Ollama uses a far-future sentinel (e.g. year 2318) to mean "keep loaded".
    if remaining > 3600:
        return "loaded"

    minutes = int(remaining // 60)
    seconds = int(remaining % 60)
    return f"{minutes}m {seconds}s"


# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------


def _mem_color(pct: float) -> str:
    if pct >= 85:
        return "red"
    if pct >= 70:
        return "yellow"
    return "green"


def _swap_color(used_mb: Optional[int], total_mb: Optional[int]) -> str:
    if not used_mb:
        return "grey50"
    if total_mb and used_mb > total_mb / 2:
        return "red"
    return "yellow"


def _temp_color(temp_c: float) -> str:
    if temp_c >= 42:
        return "red"
    if temp_c >= 38:
        return "yellow"
    return "green"


def _battery_color(pct: int) -> str:
    if pct < 20:
        return "red"
    if pct < 50:
        return "yellow"
    return "green"


# ---------------------------------------------------------------------------
# Alert badge mapping
# ---------------------------------------------------------------------------


_ALERT_LABELS = {
    "high_temp": "HIGH TEMP",
    "low_battery": "LOW BATT",
    "high_mem": "HIGH MEM",
    "stale": "STALE",
    "ollama_down": "OLLAMA DOWN",
    "never_seen": "NEVER SEEN",
}


def _alert_badges(alerts: list[str]) -> str:
    labels = [f"[{_ALERT_LABELS.get(a, a.upper())}]" for a in alerts]
    return " ".join(labels)


# ---------------------------------------------------------------------------
# Panel rendering
# ---------------------------------------------------------------------------


def _mb_to_gb(mb: Optional[int]) -> Optional[float]:
    if mb is None:
        return None
    return mb / 1024.0


def _render_field(label: str, value: Text | str, stale: bool) -> Text:
    """Compose a left-aligned label + value line, dimmed if metrics are stale."""
    text = Text()
    text.append(f"{label} ", style="dim" if stale else "")
    if isinstance(value, Text):
        if stale:
            value.stylize("dim")
        text.append_text(value)
    else:
        text.append(value, style="dim" if stale else "")
    return text


def _model_lines(status: DeviceStatus) -> list[Text]:
    """First-loaded-model line + ctx/expiry sub-line."""
    if not status.models_loaded:
        return []

    first = status.models_loaded[0]
    name = first.get("name") or first.get("model") or "?"
    extra = len(status.models_loaded) - 1

    name_line = Text()
    name_line.append("● ", style="green")
    name_line.append(name, style="bold")
    if extra > 0:
        name_line.append(f" (+{extra} more)", style="dim")

    # ctx + expiry sub-line
    details = first.get("details") or {}
    ctx = (
        first.get("context_length")
        or first.get("num_ctx")
        or details.get("context_length")
    )
    expires_str = _format_expires_at(first.get("expires_at"))

    sub = Text("  ")
    if ctx is not None:
        sub.append(f"ctx {ctx} · ", style="dim")
    sub.append(f"expires in {expires_str}" if expires_str not in ("idle", "loaded") else expires_str,
               style="dim")

    return [name_line, sub]


def _render_panel(status: DeviceStatus, width: int = 48) -> Panel:
    stale = status.metrics_stale

    # Extra vertical breathing room for wide (phone full-screen) panels.
    padding = (1, 2) if width >= 60 else (0, 1)
    # Inner content width: border (1 each side) + actual left/right padding.
    inner_w = width - 2 - padding[1] * 2
    # Scale bar to fill available space; cap at 40 so wide terminals stay sane.
    # Labels are 5 chars ("Mem  "), stats suffix ≈ 18 chars (" 80%  6.4 / 8.0 GB").
    bar_width = min(40, max(10, inner_w - 23))

    # ----- Title -----
    title = Text()
    title.append(status.name, style="bold")
    title.append(f" [{status.tier.upper()}]", style="cyan")

    badges = _alert_badges(status.alerts)
    subtitle = Text(badges, style="bold red") if badges else None

    # ----- Body -----
    lines: list[Text] = []

    # Ollama status header — always shown, never blocks system metrics
    if not status.ollama_ok and not stale:
        unreachable = Text()
        unreachable.append("✗ ", style="red")
        unreachable.append("Ollama unreachable", style="red")
        lines.append(unreachable)
    elif status.models_loaded:
        lines.extend(_model_lines(status))
    else:
        idle_line = Text()
        idle_line.append("○ ", style="dim")
        idle_line.append("idle", style="dim")
        if status.models_available:
            idle_line.append(f"  · {status.models_available[0]}", style="dim")
        lines.append(idle_line)

    # ----- Memory -----
    if status.mem_used_pct is not None and status.mem_total_mb is not None:
        color = _mem_color(status.mem_used_pct)
        bar = _bar(status.mem_used_pct, bar_width)
        used_gb = _mb_to_gb(status.mem_total_mb - (status.mem_available_mb or 0))
        total_gb = _mb_to_gb(status.mem_total_mb)
        mem_val = Text()
        mem_val.append(bar, style=color)
        mem_val.append(f" {status.mem_used_pct:.0f}%", style=color)
        mem_val.append(
            f"  {used_gb:.1f} / {total_gb:.1f} GB",
            style="dim" if stale else "",
        )
        lines.append(_render_field("Mem ", mem_val, stale))
    else:
        lines.append(_render_field("Mem ", "—", stale))

    # ----- Swap -----
    if status.swap_total_mb is not None and status.swap_used_mb is not None:
        color = _swap_color(status.swap_used_mb, status.swap_total_mb)
        pct = (
            (status.swap_used_mb / status.swap_total_mb) * 100
            if status.swap_total_mb > 0
            else 0
        )
        bar = _bar(pct, bar_width)
        used_gb = _mb_to_gb(status.swap_used_mb) or 0.0
        total_gb = _mb_to_gb(status.swap_total_mb) or 0.0
        swap_val = Text()
        swap_val.append(bar, style=color)
        swap_val.append(
            f" {used_gb:.1f} / {total_gb:.1f} GB",
            style=("dim" if stale else color if color != "grey50" else "dim"),
        )
        lines.append(_render_field("Swap", swap_val, stale))
    else:
        lines.append(_render_field("Swap", "—", stale))

    # ----- Temp -----
    temp_c = (
        status.battery_temp_c
        if status.battery_temp_c is not None
        else status.cpu_temp_c
    )
    if temp_c is not None:
        color = _temp_color(temp_c)
        temp_val = Text()
        temp_val.append(f"{temp_c:.1f}°C", style=color)
        if status.battery_temp_c is not None:
            temp_val.append("  battery", style="dim")
        else:
            temp_val.append("  cpu", style="dim")
        lines.append(_render_field("Temp", temp_val, stale))
    else:
        lines.append(_render_field("Temp", "—", stale))

    # ----- Battery -----
    if status.battery_pct is not None:
        color = _battery_color(status.battery_pct)
        batt_val = Text()
        batt_val.append(f"{status.battery_pct}%", style=color)
        if status.battery_status:
            batt_val.append(f"  {status.battery_status}", style="dim")
        lines.append(_render_field("Batt", batt_val, stale))
    else:
        lines.append(_render_field("Batt", "—", stale))

    body = Group(*lines)

    border_style = "red" if badges else ("dim" if stale else "white")

    return Panel(
        body,
        title=title,
        subtitle=subtitle,
        border_style=border_style,
        title_align="left",
        subtitle_align="right",
        width=width,
        padding=padding,
    )


# ---------------------------------------------------------------------------
# Full-screen device panel (portrait phone layout)
# ---------------------------------------------------------------------------


def _render_device_panel(status: DeviceStatus, width: int) -> Panel:
    """Large-format single-device panel for on-device display.

    Labels are on their own line (uppercase, bold), bars span the full panel
    width and repeat 3 rows tall so they read clearly on high-DPI screens.
    """
    stale = status.metrics_stale
    # padding=(1,1): 1 border + 1 pad each side → inner = width - 4
    inner_w = width - 4
    bar_w   = inner_w

    sp = Text("")  # blank spacer line

    def _hdr(label: str, *parts: tuple[str, str]) -> Text:
        t = Text()
        t.append(label, style="dim bold" if stale else "bold")
        for val, sty in parts:
            t.append(val, style="dim" if stale else sty)
        return t

    def _fat_bar(pct: float, color: str, rows: int = 2) -> list[Text]:
        s = ("dim " if stale else "") + color
        return [Text(_bar(pct, bar_w), style=s) for _ in range(rows)]

    lines: list[Text] = []

    # ----- Ollama / model -----
    if not status.ollama_ok and not stale:
        t = Text()
        t.append("✗  Ollama unreachable", style="red bold")
        lines.append(t)
    elif status.models_loaded:
        first = status.models_loaded[0]
        name = first.get("name") or first.get("model") or "?"
        extra = len(status.models_loaded) - 1
        t = Text()
        t.append("● ", style="green")
        t.append(name, style="bold")
        if extra:
            t.append(f" (+{extra})", style="dim")
        lines.append(t)
        details = first.get("details") or {}
        ctx = (first.get("context_length") or first.get("num_ctx")
               or details.get("context_length"))
        expires_str = _format_expires_at(first.get("expires_at"))
        sub = Text("  ")
        if ctx:
            sub.append(f"ctx {ctx}  ·  ", style="dim")
        sub.append(
            f"expires in {expires_str}" if expires_str not in ("idle", "loaded") else expires_str,
            style="dim",
        )
        lines.append(sub)
    else:
        t = Text()
        t.append("○  idle", style="dim")
        if status.models_available:
            t.append(f"  ·  {status.models_available[0]}", style="dim")
        lines.append(t)

    lines.append(sp)

    # ----- Memory -----
    if status.mem_used_pct is not None and status.mem_total_mb is not None:
        color   = _mem_color(status.mem_used_pct)
        used_gb = _mb_to_gb(status.mem_total_mb - (status.mem_available_mb or 0))
        tot_gb  = _mb_to_gb(status.mem_total_mb)
        lines.append(_hdr(
            _fw("MEMORY"),
            (_fw(f"  {status.mem_used_pct:.0f}%"), color),
            (f"  {used_gb:.1f} / {tot_gb:.1f} GB", "dim"),
        ))
        lines.extend(_fat_bar(status.mem_used_pct, color))
    else:
        lines.append(_hdr(_fw("MEMORY"), ("  —", "dim")))

    lines.append(sp)

    # ----- Swap -----
    if status.swap_total_mb and status.swap_total_mb > 0 and status.swap_used_mb is not None:
        pct     = (status.swap_used_mb / status.swap_total_mb) * 100
        color   = _swap_color(status.swap_used_mb, status.swap_total_mb)
        used_gb = _mb_to_gb(status.swap_used_mb) or 0.0
        tot_gb  = _mb_to_gb(status.swap_total_mb) or 0.0
        val_sty = "dim" if color == "grey50" else color
        lines.append(_hdr(
            _fw("SWAP"),
            (f"  {used_gb:.1f} / {tot_gb:.1f} GB", val_sty),
        ))
        lines.extend(_fat_bar(pct, color if color != "grey50" else "white"))
    else:
        lines.append(_hdr(_fw("SWAP"), ("  —", "dim")))

    lines.append(sp)

    # ----- Temp (single line — scalar, not a fill %) -----
    temp_c = (status.battery_temp_c if status.battery_temp_c is not None
              else status.cpu_temp_c)
    if temp_c is not None:
        color  = _temp_color(temp_c)
        source = "battery" if status.battery_temp_c is not None else "cpu"
        lines.append(_hdr(
            _fw("TEMP"),
            (_fw(f"  {temp_c:.1f}") + "°C", color),
            (f"  {source}", "dim"),
        ))
    else:
        lines.append(_hdr(_fw("TEMP"), ("  —", "dim")))

    lines.append(sp)

    # ----- Battery -----
    if status.battery_pct is not None:
        color = _battery_color(status.battery_pct)
        status_str = f"  {status.battery_status}" if status.battery_status else ""
        lines.append(_hdr(
            _fw("BATTERY"),
            (_fw(f"  {status.battery_pct}%"), color),
            (status_str, "dim"),
        ))
        lines.extend(_fat_bar(status.battery_pct, color))
    else:
        lines.append(_hdr(_fw("BATTERY"), ("  —", "dim")))

    # ----- Freshness footer -----
    if status.metrics_age_s is not None:
        lines.append(sp)
        age = int(status.metrics_age_s)
        lines.append(Text(
            f"updated {age}s ago",
            style="bold red" if stale else "dim",
        ))

    badges       = _alert_badges(status.alerts)
    title        = Text()
    title.append(status.name, style="bold")
    title.append(f"  {status.tier.upper()}", style="cyan")
    subtitle     = Text(badges, style="bold red") if badges else None
    border_style = "red" if badges else ("dim" if stale else "white")

    return Panel(
        Group(*lines),
        title=title,
        subtitle=subtitle,
        border_style=border_style,
        title_align="left",
        subtitle_align="right",
        width=width,
        padding=(1, 1),
    )


# ---------------------------------------------------------------------------
# Top-level render
# ---------------------------------------------------------------------------


def _is_active(status: DeviceStatus) -> bool:
    return (not status.metrics_stale) and bool(status.models_loaded)


def _render(statuses: list[DeviceStatus]) -> Group:
    active = sum(1 for s in statuses if _is_active(s))
    now_str = datetime.now().strftime("%H:%M:%S")

    header = Text()
    header.append("Hermes Fleet ", style="bold")
    header.append(f"· {len(statuses)} devices ", style="dim")
    header.append(f"· {active} active ", style="green" if active else "dim")
    header.append(f"· {now_str}", style="dim")

    panels = [_render_panel(s) for s in statuses]
    grid = Columns(panels, expand=False, equal=False, padding=(0, 1))

    return Group(header, Text(""), grid)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="dashboard",
        description="Hermes fleet telemetry dashboard (Rich TUI).",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=5.0,
        help="Refresh interval in live mode (seconds). Default: 5",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Print one snapshot and exit. No live display.",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8765,
        help="Receiver port. Default: 8765",
    )
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = _parse_args(argv)

    # Boot the push receiver in this process so system metrics show up.
    receiver.start_background(port=args.port)

    console = Console()

    if args.once:
        statuses = collector.collect_all()
        console.print(_render(statuses))
        return 0

    try:
        with Live(
            _render(collector.collect_all()),
            console=console,
            refresh_per_second=4,
            screen=False,
        ) as live:
            while True:
                time.sleep(args.interval)
                live.update(_render(collector.collect_all()))
    except KeyboardInterrupt:
        # Clean exit, no traceback. The receiver is a daemon thread so it
        # dies with the process.
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
