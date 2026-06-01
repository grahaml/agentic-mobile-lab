# Telemetry Spec 2: Device-Side Push Agent

**Depends on:** Spec 1 (receiver must be running to verify pushes land)
**Unblocks:** Spec 3 (collector consumes pushed Ollama state) and Spec 4 (dashboard renders real device data)
**Scope:** A bash script that runs in Termux on each Android phone, collects system metrics *and* Ollama state from localhost, POSTs them in a single bundle to Macbuntu, and exits. Plus a one-shot installer. No persistent process on the device.

---

## Context for the agent

These devices are 1.5b–7b LLM nodes running Ollama. RAM is the scarcest resource — every MB matters during inference. That's why this is a fire-and-forget bash script run on cron, not a daemon.

Each push is a **coherent snapshot** of one device at one moment: battery, memory, swap, CPU temp, AND the device's own Ollama state (`/api/ps` and `/api/tags`) fetched over localhost. The dashboard then doesn't need to poll any device — everything it shows comes from these pushes.

The localhost calls to Ollama (port 11434) are essentially free during inference: they read in-memory state in a separate handler thread from the model runner, and loopback skips the WiFi radio entirely. Cost is bounded and worth the architectural simplicity.

The Termux:API package (`termux-battery-status`) supplies battery data. `jq` builds the JSON cleanly — embedding raw JSON responses inside a heredoc would be brittle.

---

## Files to create

### `telemetry/agent/metrics_push.sh`

Single-file bash script. Must run cleanly under Termux's bash (4.x). Two placeholder values at the top get patched by `install.sh` — leave them clearly marked.

**Required behavior:**

1. **Collect system metrics:**
   - Battery: `termux-battery-status` → percentage, temperature (°C), status string. Missing command → `null` fields.
   - Memory: `/proc/meminfo` → `MemTotal` and `MemAvailable` in MB.
   - Swap: `/proc/swaps` line 2 → total and used in MB. Missing file → `0` for both.
   - CPU temp: first readable `/sys/class/thermal/thermal_zone*/temp`. Reported as °C with one decimal. Missing → `null`.

2. **Collect Ollama state from localhost:**
   - `OLLAMA_PS=$(curl -s --max-time 2 http://localhost:11434/api/ps | jq -c '.' 2>/dev/null || echo "null")`
   - `OLLAMA_TAGS=$(curl -s --max-time 2 http://localhost:11434/api/tags | jq -c '.' 2>/dev/null || echo "null")`
   - Both fall back to the literal string `null` if Ollama is down or the response is malformed. This is the dashboard's signal that the runtime is unhealthy while the device itself is still alive.

3. **Build the JSON bundle with `jq`:**

   ```bash
   PAYLOAD=$(jq -n \
     --arg device "$DEVICE_NAME" \
     --argjson battery_pct "${BATT_PCT:-null}" \
     --argjson battery_temp_c "${BATT_TEMP:-null}" \
     --arg battery_status "${BATT_STATUS:-unknown}" \
     --argjson mem_total_mb "${MEM_TOTAL:-null}" \
     --argjson mem_available_mb "${MEM_AVAIL:-null}" \
     --argjson swap_total_mb "${SWAP_TOTAL:-0}" \
     --argjson swap_used_mb "${SWAP_USED:-0}" \
     --argjson cpu_temp_c "${CPU_TEMP:-null}" \
     --argjson ollama_ps "$OLLAMA_PS" \
     --argjson ollama_tags "$OLLAMA_TAGS" \
     '{device: $device,
       battery_pct: $battery_pct,
       battery_temp_c: $battery_temp_c,
       battery_status: $battery_status,
       mem_total_mb: $mem_total_mb,
       mem_available_mb: $mem_available_mb,
       swap_total_mb: $swap_total_mb,
       swap_used_mb: $swap_used_mb,
       cpu_temp_c: $cpu_temp_c,
       ollama_ps: $ollama_ps,
       ollama_tags: $ollama_tags}')
   ```

4. **POST to `$COLLECTOR`:**
   - `curl -s --max-time 5 -X POST "$COLLECTOR" -H "Content-Type: application/json" -d "$PAYLOAD" &>/dev/null`
   - Always exit 0, even on failure. Cron handles cadence; we don't want retry storms.

**Two patchable placeholders at the top (clearly marked for sed):**

```bash
COLLECTOR="__COLLECTOR_URL__"   # patched by install.sh
DEVICE_NAME="__DEVICE_NAME__"   # patched by install.sh
```

**Rule about `--argjson`:** It expects valid JSON. That's why empty Ollama responses fall back to the literal string `null` — `jq` then interprets it as JSON null and emits a real JSON null in the payload. Without this, the script would crash and no metrics would push.

### `telemetry/agent/install.sh`

One-time setup script. Installs dependencies, patches placeholders, makes the script executable, schedules two cron entries (every 30 seconds = one at :00 + one at :30).

**Required signature:**

```bash
bash install.sh <macbuntu-ip> <device-name>
```

**Behavior:**
- Validates that both args are present; if not, prints usage and exits 1.
- Validates that `metrics_push.sh` exists in the same directory; if not, prints an error and exits 1.
- Installs Termux dependencies: `pkg install -y termux-api jq cronie` (no-op if already present).
- Enables cron: `sv-enable crond` (no-op if already enabled).
- Patches the two `__PLACEHOLDER__` lines in `metrics_push.sh` using `sed -i`. Use absolute paths in the patched values.
- Adds two crontab entries pointing at the absolute path of `metrics_push.sh`:
  - `* * * * * <absolute_path>`
  - `* * * * * sleep 30 && <absolute_path>`
- Does NOT add duplicate entries — check `crontab -l` first and skip if the absolute path already appears.
- Runs the script once immediately after install so the dashboard sees data within seconds.

---

## Verification

You can dry-run on Macbuntu by spoofing the Termux-specific bits. Macbuntu has `jq` and `curl` already.

```bash
# Start the Spec 1 receiver in another terminal:
cd telemetry && source .venv/bin/activate && python -c "
from telemetry import receiver; receiver.start_background(); import time; time.sleep(3600)
"

# Manually patch and run on Macbuntu. Battery fields will be null (no Termux);
# Ollama fields will also be null unless you have Ollama running locally:
cd agent
sed -e 's|__COLLECTOR_URL__|http://127.0.0.1:8765/metrics|' \
    -e 's|__DEVICE_NAME__|macbuntu-test|' \
    metrics_push.sh > /tmp/test_push.sh
bash /tmp/test_push.sh

# Verify the receiver got it (in the Python that's running the receiver):
# >>> from telemetry import receiver
# >>> receiver.get_all()
# Expected: a 'macbuntu-test' entry with all expected keys, system metrics
# from /proc, ollama_ps/ollama_tags null (or real if Ollama is local).
```

Real-device verification (when ready):

```bash
# Copy agent/ to the phone via scp/adb push, then in Termux:
bash install.sh 10.0.0.1 s10e   # use actual Macbuntu LAN IP
```

Within 5 seconds the receiver should have a `s10e` entry containing real battery, memory, AND the device's Ollama state (`ollama_ps.models` lists whatever's loaded right now, `ollama_tags.models` lists all available).

To stress the Ollama-down path: stop Ollama on the device with `pkill ollama`, wait for next push, confirm `ollama_ps` and `ollama_tags` are `null` in the received payload while system metrics remain populated. This is the signal the dashboard uses to render "device alive, Ollama down."

---

## Out of scope

- Anything Python on the device
- HTTP server on the device
- Any Ollama polling from Macbuntu (collector is now a thin reader over `receiver.get_all()` — see Spec 3)
- TLS or auth
- Retry logic
