# Spec: Galaxy S8 (The Architect) Provisioning - North American Variant

## 🎯 Objective
Provision the North American Samsung Galaxy S8 (Snapdragon G950U/W, 4GB RAM) as a dedicated compute node in the private agent swarm. Due to the locked bootloader on this variant, this node will operate in an **unrooted** capacity via a highly optimized Termux environment.

## 📱 Device State & Prerequisites
*   **Hardware**: Samsung Galaxy S8 (G950U - US / G950W - Canada)
*   **Processor**: Snapdragon 835
*   **Target OS**: Stock Android 9.0 (Pie) - Final official release.
*   **Environment**: Termux (F-Droid version) with `sshd` and `python3`.

## 🚀 Implementation Plan

### Phase 0: Data Preservation & Cleanup (CRITICAL)
Before any modifications, perform a full backup and clear the device.
1.  **Identify Meaningful Data**: Common targets include `DCIM`, `Pictures`, `Documents`, `Download`, and `WhatsApp`.
2.  **ADB Backup**: Run the following from your workstation:
    ```bash
    # Create backup directory
    mkdir -p ./S8_Backup
    
    # Pull meaningful directories
    adb pull /sdcard/DCIM/ ./S8_Backup/DCIM/
    adb pull /sdcard/Pictures/ ./S8_Backup/Pictures/
    adb pull /sdcard/Documents/ ./S8_Backup/Documents/
    adb pull /sdcard/Download/ ./S8_Backup/Download/
    adb pull /sdcard/WhatsApp/ ./S8_Backup/WhatsApp/
    ```
3.  **Factory Reset**: 
    *   Navigate to `Settings > General management > Reset > Factory data reset`.
    *   This ensures a "clean slate" with no background bloatware or legacy user accounts competing for RAM.

### Phase 1: Stock Optimization (Non-Root)
Since the bootloader is locked, we must optimize via ADB to maximize resources for the agent.
1.  **Enable Developer Options**: Tap `Build Number` 7 times.
2.  **Disable Bloatware**: Use ADB to disable heavy Samsung services:
    ```bash
    adb shell pm uninstall -k --user 0 com.samsung.android.bixby.agent
    adb shell pm uninstall -k --user 0 com.samsung.android.spay
    # Repeat for other non-essential pre-installed apps
    ```
3.  **Power Management**:
    *   `adb shell settings put global low_power_mode 0`
    *   Disable "Adaptive Battery" in Settings to prevent the system from killing the Termux background process.

### Phase 2: Termux & Environment Setup
1.  **Install Termux**: Sideload the latest APK from F-Droid.
2.  **Acquire Wake Lock**: Open Termux and select "Acquire Wake Lock" from the notification to ensure it stays alive.
3.  **Core Packages**: `pkg update && pkg upgrade && pkg install openssh python git termux-services`.
4.  **SSH Persistence**:
    *   Set password: `passwd`.
    *   Enable service: `sv-enable sshd`.
    *   Verify: `ssh -p 8022 localhost`.

### Phase 3: Swarm Integration
1.  **LLM Setup**:
    *   `python -m venv ~/.venv-llm`
    *   `~/.venv-llm/bin/pip install llm`
2.  **Network**: Assign static IP `10.0.0.21` via router DHCP reservation.
3.  **Registry**: Add `scout-s8-na` to `private-agent-runtime/swarm-agent.py`.

### Phase 4: Hardware Care
*   **Battery Safety**: Since we cannot use `acc` (root required), use a physical timer or smart plug to cycle power (e.g., 2 hours on, 4 hours off) to avoid constant 100% charge and potential battery swelling.

## 🧪 Validation
*   [ ] Device survives 24 hours without the Termux process being killed.
*   [ ] Successful inference: `~/.venv-llm/bin/llm "Hello world"`.
*   [ ] Swarm connectivity: Responds to requests from the `swarm-agent` controller.
