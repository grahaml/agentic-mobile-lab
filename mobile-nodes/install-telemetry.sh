#!/usr/bin/env bash
# Install the fleet telemetry push agent on a single provisioned device.
#
# Thin convenience wrapper around the canonical installer in this repo
# (telemetry/install-fleet.sh), scoped to one device. The device must already
# exist in telemetry/fleet.yaml.
#
# Usage:
#   bash install-telemetry.sh <device-name>
#   bash install-telemetry.sh <device-name> --collector-ip <ip>

set -u

if [ "$#" -lt 1 ]; then
    echo "usage: bash install-telemetry.sh <device-name> [--collector-ip <ip>]" >&2
    echo "  device-name must match an entry in telemetry/fleet.yaml" >&2
    exit 1
fi

DEVICE_NAME="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$SCRIPT_DIR/../telemetry/install-fleet.sh"

if [ ! -f "$INSTALLER" ]; then
    echo "ERROR: $INSTALLER not found." >&2
    exit 1
fi

echo "Installing telemetry agent on '$DEVICE_NAME' via $INSTALLER"
bash "$INSTALLER" --only "$DEVICE_NAME" "$@"
