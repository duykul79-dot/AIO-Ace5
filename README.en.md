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