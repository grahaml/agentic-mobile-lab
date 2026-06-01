#!/usr/bin/env python3
"""Control the Tapo P105 smart plug powering the mobile node fleet.

Usage:
  python3 scripts/tapo-power.py off    [--host IP]
  python3 scripts/tapo-power.py on     [--host IP]
  python3 scripts/tapo-power.py cycle  [--host IP] [--wait N]
  python3 scripts/tapo-power.py status [--host IP]

Credentials are read from ~/.tapo.env (KEY=VALUE format, chmod 600).
Third-Party Compatibility must be enabled in the Tapo app:
  Me > Third-Party Services > Third-Party Compatibility
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

from tapo import ApiClient


DEFAULT_HOST = "10.0.0.105"
DEFAULT_WAIT = 10
CREDS_FILE = Path.home() / ".tapo.env"


def _load_creds() -> tuple[str, str]:
    env: dict[str, str] = {}
    if CREDS_FILE.exists():
        for line in CREDS_FILE.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            env[k.strip()] = v.strip().strip("'\"")

    user = env.get("TAPO_USERNAME") or os.environ.get("TAPO_USERNAME", "")
    pwd = env.get("TAPO_PASSWORD") or os.environ.get("TAPO_PASSWORD", "")

    if not user or not pwd:
        print(
            "error: credentials not found — add TAPO_USERNAME and TAPO_PASSWORD to ~/.tapo.env",
            file=sys.stderr,
        )
        sys.exit(1)

    return user, pwd


async def _connect(host: str):
    user, pwd = _load_creds()
    client = ApiClient(user, pwd)
    return await client.p105(host)


async def cmd_status(host: str) -> int:
    device = await _connect(host)
    info = await device.get_device_info()
    state = "ON" if info.device_on else "OFF"
    print(f"{host}  alias={info.nickname!r}  state={state}")
    return 0


async def cmd_off(host: str) -> int:
    device = await _connect(host)
    info = await device.get_device_info()
    if not info.device_on:
        print(f"{host}: already OFF")
        return 0
    await device.off()
    print(f"{host}: turned OFF  (was ON)")
    return 0


async def cmd_on(host: str) -> int:
    device = await _connect(host)
    info = await device.get_device_info()
    if info.device_on:
        print(f"{host}: already ON")
        return 0
    await device.on()
    print(f"{host}: turned ON  (was OFF)")
    return 0


async def cmd_cycle(host: str, wait: int) -> int:
    device = await _connect(host)
    info = await device.get_device_info()
    if info.device_on:
        await device.off()
        print(f"{host}: OFF — waiting {wait}s …")
    else:
        print(f"{host}: already OFF — waiting {wait}s before turning on …")
    await asyncio.sleep(wait)
    await device.on()
    print(f"{host}: ON")
    return 0


async def _run(args: argparse.Namespace) -> int:
    if args.command == "status":
        return await cmd_status(args.host)
    if args.command == "off":
        return await cmd_off(args.host)
    if args.command == "on":
        return await cmd_on(args.host)
    if args.command == "cycle":
        return await cmd_cycle(args.host, args.wait)
    print(f"unknown command: {args.command}", file=sys.stderr)
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="tapo-power",
        description="Control the Tapo P105 smart plug at the mobile node power strip.",
    )
    parser.add_argument(
        "command",
        choices=["off", "on", "cycle", "status"],
        help="Action to perform",
    )
    parser.add_argument(
        "--host",
        default=DEFAULT_HOST,
        help=f"Plug IP or hostname (default: {DEFAULT_HOST})",
    )
    parser.add_argument(
        "--wait",
        type=int,
        default=DEFAULT_WAIT,
        help=f"Seconds between off and on during cycle (default: {DEFAULT_WAIT})",
    )
    args = parser.parse_args()

    try:
        return asyncio.run(_run(args))
    except KeyboardInterrupt:
        return 0
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
