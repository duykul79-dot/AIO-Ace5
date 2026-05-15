# Changelog

## v3.1.3 - keobamien UI/log popup cleanup

### Changed

- Renamed visible author/credit text to `@keobamien`.
- Redesigned realtime log UI.
- Removed duplicate old/raw realtime log box in Dọn rác progress card.
- Added cleanup completion reboot recommendation popup after successful Dọn nhanh / Dọn toàn bộ.
- Kept logging/export behavior unchanged.

### Verified

- WebUI inline JavaScript syntax: PASS.
- Shell syntax: PASS in previous audit.
- Zip root verified: module files are at zip root, not nested.
- Required module files verified before flash package.
