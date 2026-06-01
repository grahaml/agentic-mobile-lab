"""Telemetry push receiver — accepts HTTP POSTs from device agents.

Devices push their full state (system metrics + Ollama state) on a cron
heartbeat; this module stores the latest snapshot per device in memory and
exposes get_all() so the collector/dashboard can read it.

In-memory only — restarts wipe state. LAN-only — no auth.
"""
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn
from typing import Dict, Optional

_latest: Dict[str, dict] = {}
_lock = threading.Lock()

_server: Optional[HTTPServer] = None
_start_lock = threading.Lock()


def get_all() -> Dict[str, dict]:
    """Return a snapshot of the latest push from each device.

    Keys are device names (the "device" field from the push body).
    Values are the JSON payload that was POSTed plus a "received_at"
    float (time.time() at receipt).
    """
    with _lock:
        return dict(_latest)


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Silence the default access log; pushes happen every 30s per device
        # and would drown out the dashboard.
        pass

    def log_error(self, format, *args):
        sys.stderr.write("receiver: " + (format % args) + "\n")

    def do_POST(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length else b""

        try:
            payload = json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError):
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"invalid JSON")
            return

        if not isinstance(payload, dict) or not isinstance(payload.get("device"), str):
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"missing or invalid 'device' field")
            return

        payload["received_at"] = time.time()
        with _lock:
            _latest[payload["device"]] = payload

        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        self.send_response(404)
        self.end_headers()


class _ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def start_background(port: int = 8765) -> None:
    """Start the receiver in a daemon thread. Idempotent — calling twice
    is a no-op (second call returns immediately)."""
    global _server
    with _start_lock:
        if _server is not None:
            return
        _server = _ThreadingHTTPServer(("0.0.0.0", port), _Handler)
        thread = threading.Thread(
            target=_server.serve_forever,
            daemon=True,
            name="telemetry-receiver",
        )
        thread.start()
