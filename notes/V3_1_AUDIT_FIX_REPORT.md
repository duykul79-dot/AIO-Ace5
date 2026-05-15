# AIO Ace5 v3.1 Audit Fix Report

Date: 2026-05-13

## Result

FAIL: audit-scoped fixes were applied and package was built, but the required `sh -n` shell syntax gates could not be completed in this Windows sandbox. `sh`, Git Bash, Dash, and WSL were attempted; Git/MSYS shells failed with Win32 permission errors and WSL returned access denied.

Package: `output/AIO_Ace5_v3.1_audit_fixed.zip`

SHA256: `22A6065351C9A95C4A6B7C1FE680DFA25031579918615A6A5F1D408C22BA7F39`

## Inspected Files

- `AGENTS.md`
- `PROJECT_STATE.md`
- `TASK.md`
- `audits/new_audit_v3_0_4RC.html`
- `work/AIO_Ace5_v3_1_work/module.prop`
- `work/AIO_Ace5_v3_1_work/customize.sh`
- `work/AIO_Ace5_v3_1_work/post-fs-data.sh`
- `work/AIO_Ace5_v3_1_work/service.sh`
- `work/AIO_Ace5_v3_1_work/uninstall.sh`
- `work/AIO_Ace5_v3_1_work/webroot/run.sh`
- `work/AIO_Ace5_v3_1_work/webroot/index.html`
- `work/AIO_Ace5_v3_1_work/bin/aio_performance.sh`
- `work/AIO_Ace5_v3_1_work/bin/aio_game_spoof.sh`
- `work/AIO_Ace5_v3_1_work/bin/game_spoof_config.json`
- `work/AIO_Ace5_v3_1_work/bin/game_spoof_copg_compat.json`

## Fixes Applied

- Updated release identity to `AIO Ace5 V3.1`, `version=v3.1`, `versionCode=31000`.
- Added bind-mount verification/fallback logging in `post-fs-data.sh` and `service.sh`.
- Improved mount detection by checking `/proc/mounts` before falling back to `mount`.
- Hardened COPG shim ownership with `.aio_signature_v31` and removed unsafe whole-directory COPG deletion paths.
- Removed the shipped `/mnt/data` path leak from `bin/game_spoof_config.json`.
- Added missing uninstall rollback for persistent props set by cooldown.
- Improved Sạc Max votable logging/status around `/proc/oplus-votable` writes without adding charge override targets.
- Improved Shutdown thermal disable warning/status lifecycle while preserving default OFF and two-step confirmation.
- Hardened the unreachable `webroot/run.sh` default dispatch branch to explicit error exit.

## Changed Files

- `work/AIO_Ace5_v3_1_work/module.prop`
- `work/AIO_Ace5_v3_1_work/post-fs-data.sh`
- `work/AIO_Ace5_v3_1_work/service.sh`
- `work/AIO_Ace5_v3_1_work/uninstall.sh`
- `work/AIO_Ace5_v3_1_work/webroot/run.sh`
- `work/AIO_Ace5_v3_1_work/webroot/index.html`
- `work/AIO_Ace5_v3_1_work/bin/aio_extreme_generator.sh`
- `work/AIO_Ace5_v3_1_work/bin/aio_game_spoof.sh`
- `work/AIO_Ace5_v3_1_work/bin/aio_performance.sh`
- `work/AIO_Ace5_v3_1_work/bin/debloat.sh`
- `work/AIO_Ace5_v3_1_work/bin/game_spoof_config.json`
- `notes/V3_1_AUDIT_FIX_REPORT.md`

## Verification

- `node -e "...JSON.parse..."`: PASS for `bin/game_spoof_config.json` and `bin/game_spoof_copg_compat.json`.
- Grep no `/mnt/data` in non-binary module files: PASS.
- Grep no stale `v3.0.3RC` / `V3.0.3 RC` / `v3.0.4RC` / `V3.0.4 RC` in non-binary module files: PASS.
- Grep no direct `current_now` / `charge_control_limit` writes: PASS.
- Grep no `fastboot`, `curl`, or `wget` in non-binary module files: PASS.
- `sh -n customize.sh post-fs-data.sh service.sh uninstall.sh webroot/run.sh`: BLOCKED by missing/blocked shell runtime.
- `sh -n bin/*.sh`: BLOCKED by missing/blocked shell runtime.

## Unresolved Risks

- Shell syntax was not verified by `sh -n` because available Unix shells could not start in this sandbox.
- No dynamic device test was run on ColorOS/SM8650 hardware.
- Existing binary strings in `zygisk/*.so` still reference `/data/adb/modules/COPG`; binaries were not modified per instruction.
