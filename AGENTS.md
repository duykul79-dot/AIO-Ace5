# AGENTS.md  AIO Ace5 v3.1 Workspace

## Mission
Build AIO Ace5 v3.1 from v3.0.4RC modified baseline by fixing audit findings only.

## Absolute rules
- Inspect before editing.
- Smallest patch only.
- No scope expansion.
- No unrelated refactor.
- Stop on failed verification gate.
- Preserve Vietnamese UI unless audit requires warning text.
- Do not add adb, fastboot, curl, wget.
- Do not add new boot auto-run, daemon, scheduled task, or background loop.
- Do not add bank/root-hide bypass, anti-cheat bypass, stealth, or app-specific evasion.
- Do not modify zygisk/*.so or bin/copg_engine/*.
- Do not change cleanup/debloat/battery core behavior unless required by audit.

## Baseline
- Workdir: work/AIO_Ace5_v3_1_work
- Audit: audits/new_audit_v3_0_4RC.html
- Output: output/AIO_Ace5_v3.1_audit_fixed.zip

## Target release identity
- name=AIO Ace5 V3.1
- version=v3.1
- versionCode=31000

## Required fixes
1. Fix v3.0.3RC/v3.0.4RC version mismatch.
2. Add safe bind-stub verify/fallback in post-fs-data.sh.
3. Harden COPG uninstall ownership verification; avoid unsafe rm -rf /data/adb/modules/COPG.
4. Remove /mnt/data path leak from game_spoof_config.json.
5. Improve Sạc Max logging/status around /proc/oplus-votable writes; do not expand charge overrides.
6. Improve Shutdown thermal disable warning/lifecycle; keep default OFF and two-step confirm.
7. Add missing uninstall prop rollback for props set by this module.
8. Harden webroot/run.sh unreachable default branch.
9. Improve mount detection if touched.

## Verification gates
Run:
- sh -n customize.sh post-fs-data.sh service.sh uninstall.sh webroot/run.sh
- sh -n bin/*.sh
- JSON parse for bin/game_spoof_config.json and bin/game_spoof_copg_compat.json
- grep: no /mnt/data remains
- grep: no stale v3.0.3RC identity remains except audit notes
- grep: no adb/fastboot/curl/wget added
- grep: no direct current_now/charge_control_limit write added
- package zip to output/AIO_Ace5_v3.1_audit_fixed.zip
- write notes/V3_1_AUDIT_FIX_REPORT.md
