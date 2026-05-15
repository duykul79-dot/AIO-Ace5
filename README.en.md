# AIO Ace5

**AIO Ace5** is a customization module for **OnePlus Ace 5 / PKG110** running **ColorOS / OPlus**, designed for rooted environments such as **KernelSU**, **Magisk**, and **APatch**.

The module focuses on **Debloat**, **Cleanup**, **Battery**, **Performance**, **WebUI**, **Realtime Log**, **Zygisk component**, and log/report export for easier checking, auditing, and debugging.

> Author / Telegram: **@keobamien**  
> Credits: **Copg+ Extreme**

Vietnamese version: [README.md](README.md)

---

## Overview

AIO Ace5 brings common rooted-device maintenance and optimization tasks into a clean WebUI.

Main goals:

- Reduce unnecessary apps and services.
- Clean cache and junk files more conveniently.
- Display battery reports in a readable format.
- Provide practical performance, game, charging, and touch-related options.
- Support Zygisk-related components for root-dependent features.
- Show task progress through realtime logs.
- Export logs/reports for easier checking and auditing.
- Keep the user experience simple, clear, and easier to inspect.

---

## Target Device

This module is mainly developed for:

- Device: **OnePlus Ace 5**
- Model: **PKG110**
- Platform: **ColorOS / OPlus**
- Root environment: **KernelSU / Magisk / APatch**
- Architecture: **arm64-v8a**

Other devices or ROMs may not be fully compatible.

---

## Requirements Before Use

Recommended environment:

- Rooted device using **KernelSU**, **Magisk**, or **APatch**.
- **Zygisk enabled** if supported by the root environment.
- Reboot after enabling Zygisk.
- Reboot after flashing the module.
- Recommended ROM base: **ColorOS / OPlus** for OnePlus Ace 5 / PKG110.
- Keep a known-good module build for rollback.

### Zygisk Note

This module includes a Zygisk component under:

```text
zygisk/
Some features such as game spoof, compatibility layers, or Zygisk-dependent behavior may not work fully if Zygisk is not enabled.

If you are using KernelSU, APatch, or Magisk, check your root manager settings and enable Zygisk if the option is available.

Main Features
1. Debloat

The Debloat tab handles unnecessary packages using a predefined catalog.

Goals:

Reduce unnecessary apps and services.
Reduce unwanted background activity.
Keep operations controlled through the WebUI.
Reduce risk by grouping packages clearly.
Avoid unwanted automatic background debloat behavior.

Note: Debloat operations may affect apps or system services. Read the descriptions inside the WebUI carefully before running them.

2. Cleanup

The Cleanup tab provides two modes:

Quick Cleanup: quickly clears selected safe cache/junk areas.
Full Cleanup: performs a deeper cleanup and may take longer.

After Quick Cleanup or Full Cleanup finishes successfully, the WebUI shows a reboot recommendation popup to help the system release resources and run more stably.

3. Battery

The Battery tab generates and displays battery-related reports.

Goals:

Collect useful battery information.
Display results in a readable WebUI format.
Reduce the need to manually read raw logs.
Help users quickly inspect battery condition and usage.
Provide quick battery-related information for review.
4. Performance

The Performance tab focuses on practical optimization options.

Depending on the module version, feature groups may include:

Game Max
Charge Max
360Hz Touch
Game spoof / game profiles
Related system performance controls

Some performance changes may require a reboot to fully take effect.

5. Realtime Log

The module includes a Realtime Log UI for monitoring task progress directly inside the WebUI.

In v3.1.3:

The realtime log UI was redesigned for a cleaner and more consistent look.
The duplicate old log box in the Cleanup tab was removed.
The newer readable log card was kept.
Backend log/export behavior was not changed.
Task progress is easier to follow during operations.
6. Report / Log Export

The module supports logs and reports for easier checking, auditing, and bug reporting.

Depending on the feature, logs may be written to temporary system locations or exported to internal storage. When reporting issues, include screenshots and relevant logs whenever possible.

Current Version

AIO Ace5 v3.1.3

Highlights:

Updated visible author text to @keobamien.
Redesigned the realtime log UI.
Removed the duplicate old realtime log box in the Cleanup tab.
Added a reboot recommendation popup after successful Quick Cleanup / Full Cleanup.
Added clearer notes about the Zygisk requirement.
Kept backend logging/export behavior unchanged.
Preserved the main Debloat, Cleanup, Battery, and Performance logic.
Installation
Download the .zip file from GitHub Releases.
Verify the SHA256 checksum if a .sha256 file is provided.
Flash the module through KernelSU, Magisk, or APatch.
Reboot the device after flashing.
Enable Zygisk if your root environment supports it and the feature requires it.
Reboot again if you have just enabled Zygisk.
Open the module WebUI from your root/module manager.
Use each tab as needed.
Uninstallation

Remove the module from KernelSU, Magisk, or APatch.

After uninstalling, reboot the device to let the system return to a stable state.

Repository Structure
workspace_v3_1
├─ docs
│  └─ CHANGELOG.md
├─ input
├─ output
├─ work
│  └─ AIO_Ace5_v3_1_3_work
├─ README.md
├─ README.en.md
└─ .gitignore

Description:

work/AIO_Ace5_v3_1_3_work/: main module source.
output/: packaged flashable ZIP files.
input/: original input ZIP files or source inputs.
docs/: changelog and development notes.
Releases

Official flashable ZIP files should be downloaded from the Releases tab, not directly from the source tree.

Each release should include:

.zip package
.sha256 checksum
Release notes
Clear version number

Always verify the SHA256 checksum before flashing.

Bug Reports

When reporting an issue, provide:

Module version.
Device and ROM.
Root environment: KernelSU, Magisk, or APatch.
Zygisk status: enabled or disabled.
Screenshot of the issue.
Logs if available.
Steps to reproduce the issue.
Warning

This module modifies behavior in a rooted system environment. Incorrect usage may cause app issues, system service issues, battery drain, overheating, or bootloop.

Use it at your own risk.

Recommendations:

Back up important data before use.
Do not flash if you do not understand the risks.
Do not use on untested devices or ROMs.
Always keep a known-good module build for rollback.
Do not toggle multiple advanced features repeatedly if you do not understand their effects.
After major operations such as cleanup, debloat, or enabling performance features, reboot the device for better stability.
Credits
Author / Telegram: @keobamien
Credits: Copg+ Extreme
Disclaimer

This module is provided for personal use, testing, and rooted-device customization. The author is not responsible for any damage, data loss, system failure, or other risks caused by using this module.