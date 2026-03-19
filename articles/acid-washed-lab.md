# Acid-Washed: The Mobile Agent Lab (Part 2)

**The Journey:** In [Part 1: The Private Agent Runtime](./private-agent-runtime.md), we built a secure, zero-trust k3d cluster on a Linux host to sandbox AI agents. We then envisioned an [Agentic Mobile Lab](./agentic-mobile-lab.md)—a fleet of recycled devices acting as specialized "Security Analysts." 

**The Reality:** We didn't expect that turning "old phones" into "cluster nodes" would become a multi-day odyssey of bootloader combat and hardware defiance. This is the story of the "Acid-Washed" phase—where the clean Kubernetes manifests met the messy, shattered reality of reclaimed silicon.

---

### I. The Prodigy: Motorola Edge (2023)
The gold standard. Motorola gives you the keys to your own house.
*   **The Path:** `fastboot oem get_unlock_data` → Web Form → Unlock Code. 
*   **The Technical "Win":** Because the bootloader was unlocked, we didn't just run an app; we owned the kernel.
    *   **Rooting:** We pulled the `init_boot.img` via ADB, patched it with Magisk, and flashed it back:
        ```bash
        fastboot flash init_boot magisk_patched.img
        fastboot reboot
        ```
    *   **The Upgrade:** We bootstrapped a full **Ubuntu 24.04 (Noble Numbat)** userland in `/data/local/ubuntu`. This was crucial for Python 3.12 compatibility, ensuring our mobile agents could run the same modern stack as the primary k3s cluster.
    *   **Performance:** The Dimensity 7030 SoC handles `qwen2.5-coder:1.5b` at ~12 tokens/sec. 

### II. The Wall: Samsung S10e (SM-G970W)
The North American Snapdragon model. A digital vault with no reachable handle.
*   **The Struggle:** Bootloader locked tight. Knox security standing guard. No root, no chroot, no peace. We were forced to live entirely within the Termux userland.
*   **The Pivot:** Native Termux `ollama` builds.
    *   **The "Phantom" Fix:** Android 12’s "Phantom Process Killer" is a silent assassin for LLMs. We had to lobotomize the OS via ADB to let the agent breathe:
        ```bash
        adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
        ```
    *   **The "Safe" Environment:** To comply with PEP 668, we built an isolated Python 3.11 ecosystem in a virtual environment (`~/.venv-llm`), avoiding "externally managed environment" errors.

### III. The Zombie: Essential PH-1
Ancient (2017) and a screen shattered into a spiderweb of ghost-inputs.
*   **The Resurrection:** Essential was built for tinkerers. We forced LineageOS 22.2 (Android 15) onto it to get a modern kernel and **Ubuntu 24.04** in a chroot.
*   **The Battle of the Ghost Touches:** The screen was a nightmare of random inputs that would close shells, delete code, and phantom-click "Factory Reset." We ended up operating like blind submarine captains, navigating entirely via `adb shell input tap X Y` coordinates and `scrcpy --no-control`.
*   **The Pivot to Matrix:** With only 4GB of RAM, running `ollama` alongside the OS was pushing the silicon to its breaking point. We pivoted: instead of a heavy inference node, the PH-1 became our **Matrix Home Server**. By running a lightweight Synapse instance, we transformed the zombie into a private messaging gateway, allowing us to "talk" to the rest of the cluster via a secure, local-first chat protocol.

---

The goal wasn't just "Ollama on a phone." It was sovereignty over the hardware we already owned—washing away the manufacturer's limitations with a bit of technical acid to build a truly private, distributed AI swarm.
