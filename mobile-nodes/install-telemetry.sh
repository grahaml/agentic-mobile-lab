#!/usr/bin/env bash
# Install the Hermes fleet telemetry push agent on a freshly provisioned device.
#
# Wraps the canonical installer in the sibling hermes-experimentation repo so
# the source of truth (the bash agent + cron setup) stays in one place.
# Run this from your laptop after the device has been added to
# hermes-experimentation/langgraph/persona_config.yaml.
#
# Usage:
#   bash install-telemetry.sh <device-name>
#   bash install-telemetry.sh <device-name> --collector-ip <ip>
#
# Env vars:
#   HERMES_REPO   Path to the hermes-experimentation repo.
#                 Default: ../../hermes-experimentation relative to this script.

set -u

if [ "$#" -lt 1 ]; then
    echo "usage: bash install-telemetry.sh <device-name> [--collector-ip <ip>]" >&2
    echo "  device-name must match an entry in hermes-experimentation/langgraph/persona_config.yaml" >&2
    exit 1
fi

DEVICE_NAME="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_HERMES="$(cd "$SCRIPT_DIR/../../hermes-experimentation" 2>/dev/null && pwd || true)"
HERMES_REPO="${HERMES_REPO:-$DEFAULT_HERMES}"

if [ -z "$HERMES_REPO" ] || [ ! -d "$HERMES_REPO" ]; then
    echo "ERROR: hermes-experimentation repo not found." >&2
    echo "  Set HERMES_REPO=/path/to/hermes-experimentation or symlink it as" >&2
    echo "  a sibling of private-agent-runtime." >&2
    exit 1
fi

INSTALLER="$HERMES_REPO/telemetry/install-fleet.sh"
if [ ! -f "$INSTALLER" ]; then
    echo "ERROR: $INSTALLER not found. Is hermes-experimentation up to date?" >&2
    exit 1
fi

echo "Installing telemetry agent on '$DEVICE_NAME' via $INSTALLER"
bash "$INSTALLER" --only "$DEVICE_NAME" "$@"
