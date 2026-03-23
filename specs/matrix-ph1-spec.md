# Spec: Matrix Home Server on Essential PH-1 (The Zombie)

## 🎯 Objective
Transform the Essential PH-1 (4GB RAM) into a dedicated, high-availability Matrix Home Server to serve as the secure communication backbone for the private agent cluster.

## 📱 Device State & Prerequisites
*   **Hardware**: Essential PH-1 (Mata)
*   **OS**: LineageOS (Rooted)
*   **Environment**: Termux with `termux-services` and `termux-boot` installed.
*   **Dependencies**:
    *   Python 3.10+ (for Synapse) or Go (if using Dendrite/Conduit).
    *   `libsqlite` or a dedicated PostgreSQL instance (preferred for performance).
    *   `openssl`, `libffi`, `libjpeg-turbo`.

## 🏗️ Architecture
*   **Homeserver**: [Conduit](https://conduit.rs/) (Recommended for low-resource devices) or [Synapse](https://github.com/element-hq/synapse).
*   **Database**: SQLite (initial) -> PostgreSQL (if scaling).
*   **Storage**: External SD card (if available) or internal `/data/data/com.termux/files/home/matrix` directory.
*   **Network**: Fixed IP via Homelab router (`10.0.0.20`).
*   **Security**: E2EE enabled by default; no public federation (Lab-only).

## 🚀 Implementation Plan

### Phase 1: Environment Preparation
1.  Update Termux packages: `pkg update && pkg upgrade`.
2.  Install core dependencies: `pkg install rust make clang python libffi libjpeg-turbo`.
3.  Configure storage and permissions.

### Phase 2: Matrix Installation (Conduit)
1.  Download/Build Conduit binary for ARM64.
2.  Initialize configuration (`conduit.toml`).
3.  Test initial startup and registration.

### Phase 3: Boot Persistence
1.  Create a startup script in `~/.termux/boot/`.
2.  Use `termux-services` to manage the process lifecycle.
3.  Verify the server restarts automatically after a device reboot.

### Phase 4: Observability & Dashboard
1.  **System Monitor**: Install `btop` for CLI-based monitoring.
2.  **Service Health**: Simple health-check script reporting to a local dashboard.
3.  **Log Rotation**: Ensure `/var/log` (or Termux equivalent) doesn't fill internal storage.

## 🧪 Validation
*   [ ] Can register a new user via Element (Mobile/Web).
*   [ ] Can send/receive messages between two devices on the `Homelab-Net-5G`.
*   [ ] Service survives a hard reboot of the PH-1.
*   [ ] CPU/RAM usage stays within acceptable limits (< 1GB RAM).
