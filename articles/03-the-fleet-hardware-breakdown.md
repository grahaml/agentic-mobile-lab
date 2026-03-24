# Part 3: The Fleet (Hardware Breakdown & Trenches)

**The Journey:** In [Part 1](./01-the-foundation-k3s-sandbox.md), we built a secure k3s cluster on an Ubuntu 24.04 host. In [Part 2](./02-the-realization-mobile-agents.md), we established the architecture to bridge old Android phones into that cluster as AI worker nodes via SSH and Termux.

**The Reality:** We didn't expect that turning "old phones" into "cluster nodes" would become a multi-day odyssey of bootloader combat and hardware defiance. This is the story of the "Acid-Washed" phase—where the clean Kubernetes manifests met the messy, shattered reality of reclaimed silicon.

---

## I. The Prodigy: Motorola Edge (2023)
*The gold standard. Motorola gives you the keys to your own house.*

*   **The Path:** `fastboot oem get_unlock_data` → Web Form → Unlock Code. 
*   **The Technical "Win":** Because the bootloader was unlocked, we didn't just run an app; we owned the kernel.
    *   **Rooting & The Chroot:** We pulled the `init_boot.img` via ADB, patched it with Magisk, and bootstrapped a full **Ubuntu 24.04** userland in `/data/local/ubuntu`. This allowed the mobile agent to run the same modern stack as our primary k3s cluster.
    *   **Dashboard V2:** We deployed our "Observability V2" stack directly into the Termux layer. Using a dedicated `start-dashboard.sh` script, it launches a `tmux` session on boot that perfectly partitions a `gotop` resource monitor and a chroot-aware `ollama ps` watch, running silently in the background.
    *   **Performance:** The Dimensity 7030 SoC easily handles `qwen2.5-coder:1.5b` directly on the device.

## II. The Wall: Samsung S10e (SM-G970W)
*The North American Snapdragon model. A digital vault with no reachable handle.*

*   **The Struggle:** The bootloader was locked tight. Knox security stood guard. There was no root, no chroot, no peace. We were forced to live entirely within the unprivileged Termux userland.
*   **The Pivot:** Native Termux `ollama` builds.
    *   **The "Phantom" Fix:** Android 12’s "Phantom Process Killer" is a silent assassin for LLMs. It would violently terminate the Ollama server in the middle of inference. We had to lobotomize the OS via ADB to let the agent breathe:
        ```bash
        adb shell "/system/bin/device_config put activity_manager max_phantom_processes 2147483647"
        ```
    *   **The Environment:** We built an isolated Python virtual environment (`~/.venv-llm`) to comply with PEP 668 and ran Ollama natively. 
    *   **Dashboard V2:** Just like the Prodigy, the S10e was upgraded to our `tmux`-based Dashboard V2, successfully maintaining a stable `ollama serve` and resource monitor despite its lack of root.

## III. The Zombie: Essential PH-1
*Ancient (2017) and a screen shattered into a spiderweb of ghost-inputs.*

*   **The Battle of the Ghost Touches:** The screen was a nightmare of random inputs that would close shells, delete code, and phantom-click system dialogs. We operated like blind submarine captains, suppressing the rogue inputs via a custom `disable_touch.sh` script (`chmod 000 /dev/input/hbtp_input`) entirely over SSH and ADB.
*   **The Pivot to Matrix:** With only 4GB of RAM, running `ollama` alongside the OS pushed the silicon to its breaking point. We pivoted: instead of a heavy inference node, the PH-1 is designed to become our **Matrix Home Server**. By running a lightweight Synapse/Conduit instance, we are transforming the zombie into a private messaging gateway.

## IV. The Architect: Samsung S8 (SM-G950W)
*The unrooted veteran, currently being integrated.*

*   **The Future:** Our final active node in the drawer. Like the S10e, it's locked down, but it represents the "Architect" persona. Its integration via standard Termux bridging is the final piece of our active lab hardware puzzle.

---

The goal of the Private Agent Runtime wasn't just "Ollama on a phone." It was sovereignty over the hardware we already owned—washing away the manufacturer's limitations with a bit of technical acid to build a truly private, distributed AI swarm.
