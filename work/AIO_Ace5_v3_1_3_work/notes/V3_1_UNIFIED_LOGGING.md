# AIO Ace5 v3.1 — Unified Logging

## Mục tiêu

Unified logging thêm một lớp log chuẩn để audit dễ hơn, chạy song song với log cũ. Thay đổi này không thay thế log hiện có, không đổi WebUI parser, không đổi route và không đổi core logic của các script.

## Format chuẩn

```text
[YYYY-MM-DD HH:MM:SS] [AIO] [module] [LEVEL] event key=value key=value
```

Ví dụ:

```text
[2026-05-14 10:22:31] [AIO] [cleanup] [INFO] START module=clean auto=1 fast=1
[2026-05-14 10:22:45] [AIO] [cleanup] [SUMMARY] done module=clean status=ok errors=0 warnings=0 skipped=0 fast=1
```

## Levels

- `DEBUG`
- `INFO`
- `PROGRESS`
- `OK`
- `WARN`
- `ERR`
- `FATAL`
- `SUMMARY`

## Module names

- `cleanup`
- `debloat`
- `battery`
- `performance`
- `touch360`
- `game_spoof`
- `service`
- `postfs`
- `uninstall`
- `webui`

## Helper

File helper chung:

```text
bin/aio_log.sh
```

Yêu cầu thiết kế:

- POSIX shell compatible.
- Không bashism.
- Không dùng `local`, arrays, `[[ ]]`, `pipefail`.
- Không gọi `adb`, `fastboot`, `curl`, `wget`.
- Không tự ghi file log riêng.
- Chỉ print stdout.
- Có fallback timestamp nếu `date` lỗi.

## Script đã tích hợp

Phase 1 / core:

- `bin/cleanup_ace5_v10_5.sh`
- `bin/debloat.sh`
- `bin/aio_performance.sh`

Phase 2 / audit coverage:

- `bin/battery_aio_report_v1.sh`
- `bin/battery_aio_quick_input_v1.sh`
- `bin/battery_input_collector_v1_1.sh`
- `bin/battery_actor_analyzer_v1_2_2.sh`
- `bin/touch_360_worker.sh`
- `bin/aio_game_spoof.sh`

## Nguyên tắc tích hợp

- Log chuẩn được thêm song song với log cũ.
- Không xóa hoặc đổi format log cũ.
- Không sửa WebUI parser.
- Không sửa `webroot/run.sh`.
- Không sửa `service.sh`, `post-fs-data.sh`, `uninstall.sh`, `sepolicy.rule`.
- Không thêm boot auto-run, daemon, scheduled task hoặc background loop mới.
- Touch360 chỉ thêm log vào worker hiện có, không đổi interval, PID/state path hoặc logic apply/reapply.
- Game spoof chỉ thêm START/SUMMARY/ERR quanh action hiện có, không đổi profile, target, COPG shim hoặc rollback.

## Ghi chú audit catalog

Catalog hiện tại có:

- recommended: 38
- optional: 40
- cooldown: 19
- total: 97

Hai package SIM mới có trong catalog:

- `com.android.simappdialog`
- `com.android.stk`

Lưu ý: trước đó có ghi “total dự kiến 98”, nhưng audit trên file hiện tại đếm được 97 dòng hợp lệ. Task unified logging không sửa catalog để tránh đổi scope.

## Quick audit commands

```sh
sh -n bin/aio_log.sh
sh -n bin/cleanup_ace5_v10_5.sh
sh -n bin/debloat.sh
sh -n bin/aio_performance.sh
sh -n bin/battery_aio_report_v1.sh
sh -n bin/battery_aio_quick_input_v1.sh
sh -n bin/battery_input_collector_v1_1.sh
sh -n bin/battery_actor_analyzer_v1_2_2.sh
sh -n bin/touch_360_worker.sh
sh -n bin/aio_game_spoof.sh
sh -n webroot/run.sh
```

Forbidden command check for new changes:

```sh
grep -RInE 'adb|fastboot|curl|wget' bin webroot *.sh
```

## Phase 3.1 - Auto report file

Updated `bin/aio_log.sh` so every standardized `[AIO]` log line is printed to stdout and appended automatically to:

```text
/sdcard/Download/report/log.txt
```

Fallback path if the primary Download path cannot be created:

```text
/sdcard/downloads/report/log.txt
```

This keeps WebUI output unchanged while making logs easy to collect after running any module action. The helper only writes standardized unified log lines; existing legacy/raw output remains unchanged.
