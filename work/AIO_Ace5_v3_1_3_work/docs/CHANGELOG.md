# Changelog

## v3.1.7 - cooldown rollback fix

### Fixed

- Snapshot Cooldown package and prop state before enabling.
- Restore Cooldown from the snapshot instead of enabling every Cooldown package.
- Keep packages that were disabled before Cooldown disabled after turning Cooldown off.
- Skip not installed or unknown package states safely.

## v3.1.6 - separate Game Max and Game Spoof switches

### Changed

- Separated Game Max and Game Spoof into independent switches.
- Game Max no longer auto-enables/disables Game Spoof.
- Game Spoof no longer auto-enables/disables Game Max.
- Preserved quick status refresh and busy UI feedback.

## v3.1.5 - live progress UI refinement

### Changed

- Moved live progress/status card upward.
- Hid detailed realtime log lines from WebUI.
- Kept progress bar/status visible so users know tasks are running.
- Preserved backend log/export behavior.
