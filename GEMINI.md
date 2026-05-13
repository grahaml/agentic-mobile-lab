# Private Agent Runtime aka Secure Agent Cluster

This repository houses scripts and documents for setting up and operating a k3s cluster and a bunch of distributed mobile devices linked as services.

This is sometimes referred to as: homelab, mobile lab, zombie cluster, the cluster.

See README.md for information.

## Swarm & Mobile Operations
- **Device Targeting:** Target specific devices using their IDs (e.g., `architect-sm-g986w`, `scout-motorolaedge2023`).
- **Vault Workflow:** Respect the `task-<id>.md` inbox/outbox flow for worker communication.
- **Adb Safety:** Always verify device connection status before running `adb` commands.

## Interaction Guidelines
- **Research First:** Before implementing, scan `agent-framework/` or `private-agent-runtime/` for existing utilities to avoid duplication.
- **Plan Mode:** Use `enter_plan_mode` for any changes affecting the swarm architecture, security perimeter, or hardware provisioning.
- **Validation:** Verification is not complete until relevant test scripts (e.g., `test-swarm.sh`, `test_mvw.py`) have been executed successfully.

## Testing Guidelines
- **Test All Changes**: all scripts are meant to be idempotent. If you make changes to the cluster, then run some of the tests scripts to verify.
