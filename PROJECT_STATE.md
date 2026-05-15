# PROJECT_STATE.md  AIO Ace5 v3.1 current workspace

## Correct project root
C:\AIO-Ace5\workspace_v3_1

## Correct module worktree
C:\AIO-Ace5\workspace_v3_1\work\AIO_Ace5_v3_1_work

## Current status
- v3.1 base was audit-fixed.
- Packaging must use 7-Zip, not PowerShell Compress-Archive.
- Route regression for cleanup was fixed in webroot/run.sh.
- Clean fast mode Phase 1 was implemented in bin/cleanup_ace5_v10_5.sh.
- WebUI text was synced for clean fast mode.
- WebUI watchdog false timeout was fixed in webroot/index.html.

## Current pending task
Audit and fix Debloat catalog behavior:
- Debloat button reportedly runs but apps remain.
- Inspect bin/debloat_catalog.conf, bin/debloat.sh, webroot/run.sh, webroot/index.html.
- Add com.android.simappdialog to debloat_catalog.conf.
- Default debloat action for intended debloat apps should be uninstall.
- Verify route chain and catalog parser.

## Protected files unless explicitly required
- service.sh
- post-fs-data.sh
- uninstall.sh
- sepolicy.rule
- battery scripts
- performance scripts
- zygisk binaries
- COPG controller binaries
