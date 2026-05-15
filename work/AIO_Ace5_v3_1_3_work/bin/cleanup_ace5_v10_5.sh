#!/system/bin/sh
# ════════════════════════════════════════════════════════════════════
#  CLEANUP ALL IN ONE ACE 5  —  V10.5
#  Tác giả  : @keobamien
#  Thiết bị : OnePlus Ace 5/Pro (PKG110/PJD110) + OPPO/OnePlus (CPH*)
#             Qualcomm SM8650 | LPDDR5X | UFS 4.0 | ColorOS 15-16
#             Android 15-16 | SDK 35-36 | Root: KernelSU / Magisk / APatch
#  Yêu cầu  : Root shell (MT Manager trực tiếp, terminal, hoặc --auto)
# ════════════════════════════════════════════════════════════════════
#
# CHANGELOG V10.5 → V10.5.1 (5-way audit: Claude Architect + ChatGPT):
#
#   [FIX-10.5.1-1] _read_timed fallback: thêm SIGALRM timeout cho _READ_T_OK=0 path.
#     Evidence: GPT audit FATAL-1 — nhánh else của _read_timed không có timeout thật.
#     Claude verdict: MEDIUM (không phải FATAL): WebUI path không bao giờ chạm đây vì
#     AUTO_MODE=1 exit sớm dòng 524. Chỉ ảnh hưởng interactive mode trên runtime không
#     support read -t (rất hiếm: mksh standard có read -t, _READ_T_OK=0 chỉ khi probe
#     heredoc fail toàn bộ). Tuy nhiên fix là đúng đắn vì GPT correctly identified risk.
#     Fix: background subshell (sleep N; kill -ALRM $$) + trap 'true' ALRM để interrupt
#     blocking read. POSIX: SIGALRM thường interrupt read trên ash/dash/mksh.
#     Giữ default fallback nếu _rt2_ans rỗng sau interrupt.
#
#   [FIX-10.5.1-2] main(): log warning khi _wait_for_boot trả về 1 (timeout).
#     Evidence: GPT audit OPT-3 — return value của _wait_for_boot bị ignore trong main().
#     Claude verdict: MINOR — design intent là best-effort guard, script vẫn tiếp tục.
#     Fix: || _log "[WARN] _wait_for_boot timeout — boot_completed chưa set, tiếp tục"
#     để explicit log warning thay vì silent continue.
#
#   [FIX-10.5.1-3] WebUI bridge: migrate từ ksu.exec callback sang Promise import API.
#     Evidence: GPT audit FATAL-2 — ksu.exec(cmd, opts, cbName) là legacy callback API,
#     KSU ≥ 11397+ dùng import('/kernelsu') trả về Promise.
#     Claude verdict: HIGH CONFIRMED — nếu KSU Manager drop callback shim thì WebUI chết.
#     Fix: index.html bridge dùng 3-tier init:
#       Tier 1: import('/kernelsu') → { exec } (Promise API chính thức, ưu tiên cao nhất)
#       Tier 2: ksu.exec(cmd, '{}', cbName) callback shim (legacy fallback)
#       Tier 3: mock mode (browser preview / dev)
#
#   [FIX-10.5.1-4] run.sh: temp files scoped theo session UUID để tránh race condition.
#     Evidence: GPT audit OPT-1 — _LIVE/_DONE dùng tên cố định ca5_live.log/ca5_done.flag.
#     Claude verdict: MEDIUM — start liên tiếp nhanh có race window giữa rm và : > create.
#     Fix: _SESSION_ID=$(date +%s)_$$ — _LIVE/DONE/PID file mang session ID.
#     --poll/_stop dùng session ID từ tham số để đúng session.
#
#   [FIX-10.5.1-5] run.sh + index.html: bỏ hardcode module root.
#     Evidence: GPT audit OPT-2 — MODULE_DIR hardcode 'cleanup_ace5_v10_5' trong JS.
#     Claude verdict: MEDIUM — gãy khi repack/rename module ID.
#     Fix: run.sh thêm --info flag trả về MODULE_ROOT=<path>.
#     index.html: JS tự detect bridge path qua --info trước khi chạy module.
#
# CHANGELOG V10.4 → V10.5 (Comprehensive audit — 3 findings from v10.4 review):
#
#   [BUG-1 FIX / v10.5] mod_report banner version mismatch.
#     Evidence: mod_report dòng 1731 in "V10.2" trong khi header script,
#     SESSION START log, main_menu header đều là V10.4. Cosmetic bug —
#     sai banner đồng bộ qua session log field → nhầm lẫn khi debug cross-version.
#     Root cause: manual banner update trong mod_report bị miss qua v10.3 → v10.4.
#     Fix: đồng bộ banner thành "V10.5" (cùng dãy với main_menu, SESSION START).
#
#   [BUG-2 FIX / v10.5] _wait_for_boot: implement hàm guard cho --auto mode.
#     Evidence: [ARCH-9.5-1] changelog v9.5 tuyên bố implement _wait_for_boot
#     nhưng xuyên suốt v9.5 → v10.4 hàm này KHÔNG tồn tại trong code (desync
#     changelog/source lần 2, cùng model với SEC-10.1-1 thermal restore).
#     Impact: khi script trigger qua init.d/service.d sớm trong boot sequence,
#     AM/PM chưa init (sys.boot_completed=0) → cmd activity idle-maintenance,
#     pm art help, am send-trim-memory silent-fail hoặc block binder call.
#     Fix: implement _wait_for_boot() poll sys.boot_completed với timeout 60s.
#     Gọi đầu main() khi AUTO_MODE=1 (trước _acquire_lock). Interactive mode
#     không cần check (user đã login → boot xong). 2s poll interval tránh busy-wait.
#     POSIX /system/bin/sh compliant, set -u safe.
#
#   [BUG-3 FIX / v10.5] get_ram_kb: implement TTL 2s cache thực sự.
#     Evidence: [OPT-9.5-2] changelog tuyên bố cache 2s TTL nhưng get_ram_kb
#     v9.5 → v10.4 đọc /proc/meminfo mỗi lần gọi (desync changelog/source lần 3).
#     Biến _RAM_CACHE / _RAM_CACHE_TS khai báo global dòng 239-240 nhưng dead.
#     Impact thực tế: main_menu refresh RAM mỗi 120s + mỗi module chạy gọi
#     get_ram_kb 2-4 lần → không phải hot path, overhead nhỏ. Tuy nhiên trên
#     PKG110 MT Manager mode, /proc/meminfo đọc qua FUSE bridge có latency
#     bất định khi SELinux trong deny path.
#     Fix: implement cache với TTL 2s. Cache hit khi _now - _RAM_CACHE_TS < 2.
#     get_ram_kb trả về printf '%s' "$_RAM_CACHE" khi cache valid.
#     Cache miss: đọc meminfo → update cache + TS → printf.
#     Giữ fallback "printf '0'" khi awk fail.
#
# CHANGELOG V10.3 → V10.4 (Cross-audit synthesis — 4 AI verdict):
#
#   [FIX-10.4-1] main() AUTO_MODE: Bổ sung _REBOOT_FLAG dispatch sau mod_report.
#               Qwen CRITICAL-GAP: --reboot flag parse đúng (AUTO_MODE=1 +
#               _REBOOT_FLAG=1) nhưng _countdown_reboot không được gọi trong
#               AUTO_MODE path → --auto --reboot kết thúc không reboot.
#               Fix: INSERT if [ "${_REBOOT_FLAG:-0}" -eq 1 ]; then
#               _countdown_reboot; fi sau mod_report trong main() AUTO block.
#               _countdown_reboot tự handle AUTO_MODE+_REBOOT_FLAG=1 guard
#               (sleep 3 → reboot). ERROR_COUNT>0 vẫn block reboot.
#   [OPT-10.4-1] mod_network_reset: Wrap 4 lệnh svc wifi/data disable/enable
#               với _run_to 5 để tránh script freeze nếu system_server deadlock.
#               DeepSeek audit: svc là synchronous binder call, không có timeout
#               mặc định. _run_to 5 giới hạn wait 5s/lệnh, warn nếu timeout.
#               Không ảnh hưởng ndc/cmd connectivity (đã có || true protection).
#
# CHANGELOG V10 → V10.1 (audit: state-leak thermal restore):
#
#   [SEC-10.1-1] Thermal DPM restore trong _on_exit() — CRITICAL SAFETY FIX.
#               FIX-9.5-3 đã ghi trong changelog v9.5 nhưng KHÔNG được implement
#               vào code (lỗi desync changelog/source xuyên suốt v9.5 → v10).
#               Root cause: _on_exit() restore đầy đủ memory/UFS nhưng hoàn toàn
#               thiếu `cmd thermalservice override-status 3`.
#               Hậu quả: nếu script bị ngắt đột ngột trong khi thermal bypass
#               active (_thermal_bypassed=1), hệ thống treo ở override-status 0
#               (DISABLED) — Athena thermal HAL mất kiểm soát CPU/GPU throttling.
#               Fix: chèn guard block trước `sync` trong _on_exit(). Guard
#               ${_thermal_bypassed:-0} tránh gọi thừa, _log trước exec 3>&-.
#               POSIX /system/bin/sh compliant. Không dùng [[ ]], không bashism.
#
# CHANGELOG V10.1 → V10.2 (4-way audit: Qwen + Gemini + ChatGPT + DeepSeek):
#
#   [FIX-10.2-1] echo → printf '%s\n' cho toàn bộ sysfs/proc writes (12 locations).
#               Qwen: Kernel 6.1 GKI strict sysfs write mode có thể reject echo
#               trên /proc/sys/vm/* và /sys/block/*/queue/iostats. printf '%s\n'
#               là POSIX chuẩn, không có escape processing, guaranteed exact bytes.
#               Locations: _on_exit (L279,L289,L297), mod_boost (L1289,L1308,
#               L1311,L1324,L1334,L1344,L1349,L1354,L1368).
#               Gemini/ChatGPT/DeepSeek: PASS trên thermal/lock/timed — xác nhận
#               không có bug mới ngoài ACCEPT-2.
#   [OPT-10.2-1] LSPosed launcher resolver: thêm tr -d '\033' trước sed (L1122-1123).
#               Qwen: cmd package resolve-activity có thể trả về ANSI escape sequences
#               trong MT Manager environment ColorOS 15/16. tr strips ESC byte trước
#               sed pattern match, tránh false-empty _launcher trên tinted output.
#
# CHANGELOG V9.5 → V10 (4-way audit: Qwen + Gemini + ChatGPT + DeepSeek):
#
#   [FIX-10-1]  head -1 → head -n 1 (POSIX chuẩn, v9.5 chưa áp dụng vào code).
#   [FIX-10-2]  _read_timed fallback: seed _rt2_ans="" trước read để tránh unbound
#               dưới set -u nếu read fail sớm (ChatGPT WARN).
#   [SEC-10-1]  Bỏ vfs_cache_pressure=150 khỏi mod_boost. Changelog v9.5 [HW-9.5-2]
#               đã ghi nhưng code chưa xóa. Qwen + Gemini xác nhận: phá AI memory
#               forecast ColorOS 15/16, tăng cold-start latency.
#   [HW-10-1]   watermark_scale_factor: 250 → 150. Code v9.5 vẫn ghi 250 dù changelog
#               [HW-9.5-1] tuyên bố đã đổi. Qwen + Gemini: 250 gây kswapd liên tục
#               trên LPDDR5X 12GB. 150 = ngưỡng an toàn (Lead Dev v9.5 verdict).
#   [HW-10-2]   Xóa UFS static writes: nr_requests=128, read_ahead_kb=256. Code v9.5
#               vẫn ghi dù changelog [HW-9.5-3] tuyên bố đã bỏ. Qwen + Gemini:
#               SM8650 blk-mq+mq-deadline+HPB tự quản lý. Static override phá I/O.
#               Giữ lại iostats=0 (chỉ tắt stat accounting, không ảnh hưởng scheduling).
#   [HW-10-3]   Thermal bypass threshold: 70 → 65°C trong mod_dalvik. Qwen: Athena
#               throttle từ 72°C → cần 7°C margin. CHATGPT PASS bị override bởi
#               Safety priority (POSIX > Safety > HW > Perf > UX).
#   [OPT-10-1]  safe_umount: grep -qF " $_mpt " → awk '$2==mp' cho /proc/mounts.
#               Qwen: grep column-sensitive, false-negative nếu mount point cuối dòng
#               hoặc có ký tự đặc biệt. awk field-exact, POSIX compliant.
#   [BANNER-10] Tất cả banner/log string V9.4 → V10.
#
# CHANGELOG V9.4 → V9.5 (4-way audit: ChatGPT + DeepSeek + Qwen + Gemini):
#
#   [FIX-9.5-1]  head -n 1 thay head -1 (3 chỗ) — POSIX chuẩn.
#   [FIX-9.5-2]  Guard /proc/mounts, /proc/$pid/stat, drop_caches trước khi đọc/ghi.
#   [FIX-9.5-3]  _thermal_bypassed restore trong _on_exit trap — brick risk fix.
#   [OPT-9.5-1]  _get_cpu_temp_hot: 1-pass (dir loop, type+temp cùng iteration).
#   [OPT-9.5-2]  get_ram_kb: cache 2s TTL — giảm /proc/meminfo reads.
#   [OPT-9.5-3]  df -k parse: awk NR==2{print $4} thay 3-process pipeline.
#   [OPT-9.5-4]  LSPosed scope dedup: awk primary path (O(n)), while+grep làm fallback.
#   [HW-9.5-1]   watermark_scale_factor: 250 → 150 (Qwen: 250 gây kswapd quá mức trên
#                LPDDR5X 16/24GB, CPU wake-up liên tục, UI stutter).
#   [HW-9.5-2]   Bỏ vfs_cache_pressure=150 (Qwen: phản tác dụng, phá AI memory forecast
#                ColorOS; Android phụ thuộc inode/dentry cache cho cold-start).
#   [HW-9.5-3]   Bỏ UFS static queue tweaks (Qwen: SM8650 blk-mq + mq-deadline + HPB
#                tự quản lý động; static override phá I/O scheduling).
#   [HW-9.5-4]   Thermal bypass threshold: 70°C → 65°C (Qwen: Athena throttle từ 72°C).
#   [ARCH-9.5-1] _wait_for_boot: guard cho --auto mode — tránh boot race condition
#                (Gemini: AM chưa init khi script trigger qua service.d).
#
# CHANGELOG V9.3 → V9.4 (3-way audit: kiến trúc sư) + V9.4 → V9.4.1 (Gemini audit)
# + V9.4.1 → V9.4.2 (field log audit: CleanAce5_20260413_180525):
#
#   [BUG-LOG-1 FIX] _read_timed: $() subshell KHÔNG timeout trên mksh ColorOS.
#     Evidence: log 18:10:51 → 18:19:43 = 532s gap, prompt timeout 60s.
#     Root cause: mksh bỏ qua read -t trong $() context (SIGALRM không gửi
#     đến subshell). read block vô hạn đến khi user nhập.
#     Fix: thêm _RT_RESULT global. Tất cả caller đổi từ
#       var="$(_read_timed N def)"  → _read_timed N def; var="$_RT_RESULT"
#     _read_timed vẫn printf ra stdout để tương thích caller >/dev/null.
#
#   [BUG-LOG-2 FIX] _run_dexopt: spinner vòng lặp vô hạn sau PID reuse.
#     Evidence: log 18:25:31 → 18:26:29 còn chạy ở 362s/300s, không có SESSION END.
#     Root cause: sau khi timeout exit (T+310s), PID bị tái sử dụng bởi proc
#     khác trên Android → kill -0 $_rdx_pid luôn thành công → infinite loop.
#     Fix: hard limit = timeout + 30s grace. Nếu elapsed > limit → force kill
#     PID và break. Script không bị treo.
#
#   [INFO] pm art không khả dụng trên PKG110_15.0.0.860 (pm_art=0, SDK=35).
#     Expected: cmd package bg-dexopt-job fallback được dùng đúng cách.
#
#   [INFO] LSPosed scope config rỗng: lspd present nhưng không có */scope files.
#     User chọn skip fallback compile (đúng behavior).
#
# CHANGELOG V9.3 → V9.4 + V9.4 → V9.4.1: xem bên dưới.
#
#   [BUG-9.3-1 FIX / v9.4.1 update] safe_rm directory cleanup:
#     Root cause: V9.3 dùng -exec rm -f {} + — rm -f không xoá directories.
#     V9.4 ban đầu dùng find -delete (works on Toybox nhưng non-POSIX extension).
#     V9.4.1 (Gemini audit): đổi sang -exec rm -rf {} + — rm -rf là POSIX-compatible,
#     xoá đệ quy cả files và dirs, không phụ thuộc GNU/BSD -delete extension.
#     -mindepth + -depth + -exec rm -rf {} + = POSIX sh compliant trên Android.
#
#   [BUG-9.3-2 FIX / v9.4.1 update] mod_modules orphan cleanup: cùng root cause.
#     find -mindepth 1 -depth -exec rm -rf {} + thay cho find -delete.
#
#   [BUG-9.3-3 FIX] _run_dexopt spinner: khôi phục $_rdx_label trên terminal.
#     v9.3 bỏ label khỏi printf → user không biết job nào đang chạy.
#     Giữ nguyên elapsed/max (không % giả). Format mới: [c] label: Xs/Ys
#
# CHANGELOG V9.2 → V9.3 (được merge vào v9.4 — giữ toàn bộ fix):
#   [FIX-9.3-1] _WMK_BOOST_ORIG: watermark_boost_factor save+restore đúng.
#               v9.2 hardcode echo 0 cuối compaction, không restore về gốc.
#   [FIX-9.3-2] _thermal_safe flag: không bypass thermal khi CPU vẫn ≥70°C.
#               v9.2 luôn bypass dù CPU còn nóng sau 10s wait.
#   [FIX-9.3-3] wipe_dir: thêm -depth cho empty dir rmdir (exec rmdir {}).
#               -exec rmdir không ngầm định depth-first như -delete.
#   [OPT-9.3-1] Spinner dexopt: bỏ % time-based giả → elapsed/max thực.
#   [UX-9.3-1]  Dexopt info messages: user biết job tiếp tục chạy ngầm.
#
# CHANGELOG V9.1 → V9.2 (kiến trúc sư audit — merge 3-way v8.3/v8.4/v9.0):
#   [FIX-9.2-1] _read_timed: EINTR retry loop — tính remaining time, retry
#               khi read -t trả về sớm do kernel/SELinux EINTR.
#   [FIX-9.2-2] _read_timed: printf >&2 trực tiếp — KHÔNG dùng warn()/ui().
#               warn() → stdout bị capture trong $() → _choice = "[WARN]..."
#               → menu loop vô hạn (v8.2 bug tái phát trong v9.0).
#   [FIX-9.2-3] _read_timed: ${2-n} không phải ${2:-n} — cho phép "" làm
#               default (sentinel press-enter pause trong main_menu).
#   [FIX-9.2-4] Menu sentinel "_T_": phân biệt timeout thật vs tap/Enter rỗng.
#               read success → output raw; "_T_" chỉ từ timeout thực sự.
#   [FIX-9.2-5] _READ_T_OK probe: giữ heredoc approach (v8.3/v8.4).
#               "read -t 0 < /dev/null" chỉ test syntax, không test tty thật.
#   [PORT-9.2-1] main_menu: clear screen + header mỗi vòng (v9.0 style).
#   [PORT-9.2-2] "Nhấn Enter để tiếp tục" pause sau mỗi module.
#   [PORT-9.2-3] mod_report: WARN_COUNT hiển thị trong bảng tổng kết.
#
# CHANGELOG V8.4 → V9.x (base):
#   [FIX-1]  TTY detection: probe /dev/tty cho MT Manager
#   [FIX-2]  Dexopt spinner + progress (_run_dexopt)
#   [FIX-3]  pm art error message chính xác (pm_art flag + SDK)
#   [FIX-4]  Menu sentinel "_T_" — tap/Enter ≠ timeout
#   [OPT-1..5] awk one-liners, compact case patterns
#
# CHANGELOG V8.3: FIX-CRIT-1 warn() stdout leak, FIX-CRIT-2 read </dev/tty
# CHANGELOG V8.2: FIX-1..5 safety hardening, ADD-1 logcat clear
# ════════════════════════════════════════════════════════════════════

# ─── SHELL RUNTIME CHECK ─────────────────────────────────────────────
_sh_runtime="$(readlink /proc/$$/exe 2>/dev/null)"
[ -z "$_sh_runtime" ] && _sh_runtime="$(cat /proc/$$/comm 2>/dev/null)"
case "$_sh_runtime" in
    *mksh*|*sh*|*ash*|*dash*) ;;
    "") ;;
    *) printf "[WARN] Shell runtime lạ: %s — script target POSIX sh\n" "$_sh_runtime" ;;
esac
unset _sh_runtime

export PATH="/sbin:/system/bin:/system/xbin:/vendor/bin:/product/bin"
set -u

# ─── ARGUMENT PARSING ────────────────────────────────────────────────
AUTO_MODE=0
MODULE_ID=""   # ID module từ --module <id> (WebUI bridge path)
case "${1:-}" in
    --auto)
        AUTO_MODE=1
        printf "[INFO] --auto flag: non-interactive mode — TTY check bypass\n"
        ;;
    --reboot)
        AUTO_MODE=1
        _REBOOT_FLAG=1
        printf "[INFO] --reboot flag: auto mode + force reboot sau khi hoàn tất\n"
        ;;
    # ── WEBUI ROUTING (v10.5+) ──────────────────────────────────────
    # KSU WebUI gọi: sh run.sh --module <id>
    # Script jump thẳng đến hàm tương ứng, không menu, không TTY.
    # AUTO_MODE=1 để bypass _read_timed (dùng default an toàn).
    --module)
        MODULE_ID="${2:-}"
        if [ -z "$MODULE_ID" ]; then
            printf "[ERR] --module cần tham số ID.\n"
            printf "[ERR] Hợp lệ: clean | modules | boost | dalvik | network | all\n"
            exit 1
        fi
        AUTO_MODE=1   # bypass TTY check + _read_timed fallback-to-default
        printf "[INFO] --module %s: WebUI dispatch mode\n" "$MODULE_ID"
        ;;
    --help)
        printf "Usage: sh %s [--auto|--reboot|--module <id>|--help]\n" "$0"
        printf "  (không có flag) : Interactive TTY menu\n"
        printf "  --auto          : Non-interactive, chạy mod 1+2+3+4\n"
        printf "                    Ví dụ: adb shell su -c 'sh %s --auto'\n" "$0"
        printf "  --reboot        : Auto mode + reboot sau khi hoàn tất\n"
        printf "  --module <id>   : WebUI bridge — chạy đúng 1 module rồi thoát\n"
        printf "                    <id>: clean | modules | boost | dalvik | network | all\n"
        printf "                    Ví dụ: sh %s --module clean\n" "$0"
        printf "  --help          : In usage này\n"
        exit 0
        ;;
    "")
        AUTO_MODE=0
        ;;
    *)
        printf "[ERR] Unknown flag: %s\n" "$1"
        printf "[ERR] Dùng --help để xem usage.\n"
        exit 1
        ;;
esac

# ─── READLINK -F CHECK ───────────────────────────────────────────────
if ! readlink -f / >/dev/null 2>&1; then
    printf "[FATAL] readlink -f không được hỗ trợ.\n"
    printf "[FATAL]   export PATH=/system/bin:\$PATH\n"
    exit 1
fi

# ─── BIẾN TOÀN CỤC ──────────────────────────────────────────────────
TOTAL_FREED=0
ERROR_COUNT=0
SUCCESS_COUNT=0
SKIP_COUNT=0
WARN_COUNT=0
RAM_BEFORE=0
STEP=0
TOTAL_STEPS=0
ORPHAN_TMP=""
HOOKED_TMP=""
_UFS_RESTORE_TMP=""
_thermal_bypassed=0
_RAM_CACHE=""
_RAM_CACHE_TS=0
_THERM_DPM_FLAG="/data/local/tmp/aio_thermal_dpm_bypass_active"
CFG_LOCK_FILE="/data/local/tmp/cleanup_ace5.lock"
CFG_LOCK_DIR="${CFG_LOCK_FILE}.d"
T_START=$(date +%s)
_ts=$(date +%Y%m%d_%H%M%S)
_REBOOT_FLAG=0
CLEAN_FAST_MODE=0
CLEAN_MEASURE_SIZE=1
CLEAN_APP_CACHE_QUIET=0
AIO_LOG_HELPER="${0%/*}/aio_log.sh"
if [ -f "$AIO_LOG_HELPER" ]; then
    . "$AIO_LOG_HELPER"
else
    aio_log() {
        _module="$1"
        _level="$2"
        _event="$3"
        shift 3
        echo "[AIO] [$_module] [$_level] $_event $*"
    }
fi
# MODULE_ID được set tại ARGUMENT PARSING (trước section này).
# Giữ nguyên giá trị — KHÔNG reset về "" ở đây.
# set -u: đảm bảo luôn defined (đã init "" tại arg parsing).
: "${MODULE_ID:=}"

# ─── SDK CHECK ───────────────────────────────────────────────────────
_SDK="$(getprop ro.build.version.sdk 2>/dev/null)"
_SDK=$(printf '%s' "${_SDK:-0}" | tr -cd '0-9')
_SDK="${_SDK:-0}"

# ─── LOG FILE ────────────────────────────────────────────────────────
CFG_LOG_MAX_KB=500
if touch "/sdcard/CleanAce5_${_ts}.log" 2>/dev/null; then
    LOG="/sdcard/CleanAce5_${_ts}.log"
elif touch "/data/local/tmp/CleanAce5_${_ts}.log" 2>/dev/null; then
    LOG="/data/local/tmp/CleanAce5_${_ts}.log"
else
    LOG="/dev/null"
fi
: > "$LOG"
exec 3>>"$LOG"

# ─── FILE TẠM ────────────────────────────────────────────────────────
ORPHAN_TMP="$(mktemp /data/local/tmp/orphan_XXXXXX 2>/dev/null)" || {
    printf "[FATAL] mktemp thất bại — /data/local/tmp không ghi được. Thoát.\n"
    exit 1
}
: > "$ORPHAN_TMP"

_UFS_RESTORE_TMP="$(mktemp /data/local/tmp/ufs_restore_XXXXXX 2>/dev/null)" || true
[ -n "$_UFS_RESTORE_TMP" ] && : > "$_UFS_RESTORE_TMP"

# ─── SAVE SYSFS ORIGINALS ────────────────────────────────────────────
_WMK_SCALE_ORIG=""
[ -f /proc/sys/vm/watermark_scale_factor ] && \
    _WMK_SCALE_ORIG="$(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null)"

_VFS_CACHE_ORIG=""
[ -f /proc/sys/vm/vfs_cache_pressure ] && \
    _VFS_CACHE_ORIG="$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)"

_WMK_BOOST_ORIG=""
[ -f /proc/sys/vm/watermark_boost_factor ] && \
    _WMK_BOOST_ORIG="$(cat /proc/sys/vm/watermark_boost_factor 2>/dev/null)"

# ─── TRAP ────────────────────────────────────────────────────────────
_on_exit() {
    [ -n "${ORPHAN_TMP+set}" ] && [ -n "$ORPHAN_TMP" ] && rm -f "$ORPHAN_TMP" 2>/dev/null
    [ -n "${HOOKED_TMP+set}" ] && [ -n "$HOOKED_TMP" ] && rm -f "$HOOKED_TMP" 2>/dev/null
    rm -rf "$CFG_LOCK_DIR" 2>/dev/null

    if [ -n "${_UFS_RESTORE_TMP+set}" ] && [ -n "$_UFS_RESTORE_TMP" ] && \
       [ -f "$_UFS_RESTORE_TMP" ]; then
        while IFS= read -r _ur_line || [ -n "$_ur_line" ]; do
            [ -z "$_ur_line" ] && continue
            _ur_blk="${_ur_line%%:*}"
            _ur_rest="${_ur_line#*:}"
            _ur_param="${_ur_rest%%:*}"
            _ur_val="${_ur_rest#*:}"
            [ -n "$_ur_blk" ] && [ -n "$_ur_param" ] || continue
            _ur_val_clean="$(printf '%s' "$_ur_val" | tr -cd '0-9')"
            [ -z "$_ur_val_clean" ] && continue
            [ -f "${_ur_blk}/queue/${_ur_param}" ] && \
                printf '%s\n' "$_ur_val_clean" > "${_ur_blk}/queue/${_ur_param}" 2>/dev/null
        done < "$_UFS_RESTORE_TMP"
        rm -f "$_UFS_RESTORE_TMP" 2>/dev/null
        _UFS_RESTORE_TMP=""
    fi

    if [ -n "${_WMK_SCALE_ORIG+set}" ] && [ -n "$_WMK_SCALE_ORIG" ] && \
       [ -f /proc/sys/vm/watermark_scale_factor ]; then
        _wmk_chk="$(printf '%s' "$_WMK_SCALE_ORIG" | tr -cd '0-9')"
        if [ -n "$_wmk_chk" ]; then
            _cur="$(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null)"
            [ "$_cur" != "$_WMK_SCALE_ORIG" ] && \
                printf '%s\n' "$_wmk_chk" > /proc/sys/vm/watermark_scale_factor 2>/dev/null
        fi
    fi

    if [ -n "${_VFS_CACHE_ORIG+set}" ] && [ -n "$_VFS_CACHE_ORIG" ] && \
       [ -f /proc/sys/vm/vfs_cache_pressure ]; then
        _vfs_chk="$(printf '%s' "$_VFS_CACHE_ORIG" | tr -cd '0-9')"
        if [ -n "$_vfs_chk" ]; then
            _cur_vfs="$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null)"
            [ "$_cur_vfs" != "$_VFS_CACHE_ORIG" ] && \
                printf '%s\n' "$_vfs_chk" > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
        fi
    fi

    if [ -n "${_WMK_BOOST_ORIG+set}" ] && [ -n "$_WMK_BOOST_ORIG" ] && \
       [ -f /proc/sys/vm/watermark_boost_factor ]; then
        _wmb_chk="$(printf '%s' "$_WMK_BOOST_ORIG" | tr -cd '0-9')"
        [ -n "$_wmb_chk" ] && \
            printf '%s\n' "$_wmb_chk" > /proc/sys/vm/watermark_boost_factor 2>/dev/null
    fi

    # --- THERMAL DPM RESTORE (SEC-10.1-1 — Critical Safety Gate) ---
    # FIX-9.5-3 tuyên bố đã implement nhưng source v9.5→v10 không có dòng này.
    # Nếu script bị ngắt đột ngột (_thermal_bypassed=1 còn active), hệ thống
    # sẽ treo ở override-status 0 (DISABLED) — Athena HAL mất throttling control.
    # Guard ${_thermal_bypassed:-0}: tránh gọi thừa khi bypass chưa kích hoạt.
    # Đặt TRƯỚC exec 3>&- vì _log ghi vào FD 3.
    if [ "${_thermal_bypassed:-0}" -eq 1 ]; then
        cmd thermalservice override-status 3 >/dev/null 2>&1 \
            && _log "[EXIT] Thermal DPM restored: override-status 3 (NORMAL)" \
            || _log "[EXIT][WARN] Thermal restore thất bại — service.sh sẽ thử khôi phục ở boot sau"
        rm -f "$_THERM_DPM_FLAG" 2>/dev/null
        _thermal_bypassed=0
    fi
    sync
    exec 3>&- 2>/dev/null || true
}
trap '_on_exit' EXIT
trap 'sync; printf "\n[!] Bị ngắt. Log: %s\n" "$LOG"; exit 1' INT TERM

# ─── LOGGER / UI ─────────────────────────────────────────────────────
_log()  { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$1" >&3 2>/dev/null; }
ui()    { printf "%s\n" "$1"; _log "$1"; }
ok()    { ui "  [OK]   $1"; SUCCESS_COUNT=$((SUCCESS_COUNT+1)); }
warn()  { ui "  [WARN] $1"; WARN_COUNT=$((WARN_COUNT+1)); }
err()   { ui "  [ERR]  $1"; ERROR_COUNT=$((ERROR_COUNT+1)); }
skip()  { ui "  [SKIP] $1"; SKIP_COUNT=$((SKIP_COUNT+1)); }
_skip_quiet() { _log "  [SKIP] $1"; SKIP_COUNT=$((SKIP_COUNT+1)); }
step()  { ui "-- $1"; }
line()  { ui "──────────────────────────────────────────────────"; }

# ─── MATH HELPERS ────────────────────────────────────────────────────
safe_int() {
    _v=$(printf '%s' "$1" | tr -cd '0-9')
    printf '%s' "${_v:-0}"
}

get_ram_kb() {
    # BUG-3 FIX (v10.5): TTL 2s cache — OPT-9.5-2 đã declare biến global nhưng
    # chưa implement. Giảm /proc/meminfo reads khi main_menu refresh và module
    # gọi liên tục. Cache hit khi elapsed < 2s; miss khi stale hoặc empty.
    _rk_now=$(date +%s)
    _rk_age=$(( _rk_now - ${_RAM_CACHE_TS:-0} ))
    if [ -n "${_RAM_CACHE:-}" ] && [ "$_rk_age" -ge 0 ] && [ "$_rk_age" -lt 2 ]; then
        printf '%s' "$_RAM_CACHE"
        return 0
    fi
    _rk_val=$(awk '/^MemAvailable:/{a=$2} /^MemFree:/{f=$2} /^Cached:/{c=$2}
         END{print (a>0)?a:f+c}' /proc/meminfo 2>/dev/null || printf '0')
    _RAM_CACHE="$_rk_val"
    _RAM_CACHE_TS="$_rk_now"
    printf '%s' "$_rk_val"
}

kb_to_mb_sh() {
    _kv=$(safe_int "${1:-0}")
    printf '%d.%d MB' "$((_kv / 1024))" "$(( (_kv % 1024) * 10 / 1024 ))"
}

size_of() {
    _sz=$(du -sk "$1" 2>/dev/null)
    _sz="${_sz%%[[:space:]]*}"
    printf '%s' "${_sz:-0}"
}

# ─── PACKAGE NAME VALIDATOR ───────────────────────────────────────────
_is_valid_pkg() {
    case "${1:-}" in
        ''|.*|*.|*..*|*[!a-zA-Z0-9_.]*) return 1 ;;
    esac
    return 0
}

# ─── BOOT COMPLETION GUARD (v10.5 / ARCH-9.5-1) ─────────────────────
# Poll sys.boot_completed tối đa 60s. Tránh race condition khi script
# trigger qua init.d/service.d trước khi AM/PM init (SDK 35+ binder
# service resolution có thể block hoặc silent-fail).
# Chỉ gọi trong AUTO_MODE — interactive có nghĩa user đã login → boot xong.
_wait_for_boot() {
    # [FIX-10.5-BOOT] Fast-path: nếu máy đã boot xong thì return ngay,
    # không vào loop 60s. Trường hợp service.d trigger sớm mới cần poll.
    _wb_st="$(getprop sys.boot_completed 2>/dev/null)"
    if [ "${_wb_st:-0}" = "1" ]; then
        _log "[BOOT] sys.boot_completed=1 — boot hoàn tất, không cần chờ"
        return 0
    fi

    _wb_t=0
    _wb_max=60
    _log "[BOOT] sys.boot_completed chưa set — polling (max ${_wb_max}s)..."
    while [ "$_wb_t" -lt "$_wb_max" ]; do
        sleep 2
        _wb_t=$(( _wb_t + 2 ))
        _wb_st="$(getprop sys.boot_completed 2>/dev/null)"
        if [ "${_wb_st:-0}" = "1" ]; then
            _log "[BOOT] sys.boot_completed=1 sau ${_wb_t}s wait"
            return 0
        fi
    done
    _log "[BOOT][WARN] sys.boot_completed chưa set sau ${_wb_max}s — tiếp tục bất chấp"
    printf '[BOOT][WARN] boot timeout %ss — tiếp tục\n' "$_wb_max" >&2
    return 1
}

# ─── PROMPT READ WITH TIMEOUT ─────────────────────────────────────────
# _READ_T_OK probe: heredoc — test timed-read từ terminal thật.
# EINTR retry: tính remaining time, loop khi read trả về sớm trước timeout.
# printf >&2 trong timeout path — KHÔNG dùng warn()/ui().
# ${2-n} không phải ${2:-n}: cho phép "" làm default (sentinel press-enter).
#
# BUG-LOG-1 FIX (v9.4.1): read -t N </dev/tty trong $() subshell KHÔNG timeout
#   trên mksh ColorOS (PKG110_15.0.0.860). read block vô hạn → 532s gap thay vì
#   60s (confirmed từ log CleanAce5_20260413_180525).
#   Root cause: mksh bỏ qua -t trong $() context, vì subshell không nhận SIGALRM.
#   Fix: lưu kết quả vào global _RT_RESULT. Tất cả caller không dùng $() nữa,
#   thay bằng: _read_timed N def; var="$_RT_RESULT". printf vẫn hoạt động cho
#   caller dùng >/dev/null (press-enter pause).
_READ_T_OK=0
( read -t 1 _rtprobe <<'_RTEOF'
x
_RTEOF
) 2>/dev/null; _rt_probe_exit=$?
[ "$_rt_probe_exit" -le 1 ] 2>/dev/null && _READ_T_OK=1
unset _rt_probe_exit

_RT_RESULT=""   # Global output — tránh $() subshell block bug trên mksh

_read_timed() {
    _rt2_sec="${1:-60}"
    _rt2_def="${2-n}"
    _RT_RESULT="$_rt2_def"

    if [ "${AUTO_MODE:-0}" -eq 1 ]; then
        printf '%s' "$_rt2_def"; return 0
    fi

    if [ "$_READ_T_OK" -eq 1 ]; then
        _rt2_start=$(date +%s)
        while true; do
            _rt2_now=$(date +%s)
            _rt2_left=$(( _rt2_sec - (_rt2_now - _rt2_start) ))
            if [ "$_rt2_left" -le 0 ]; then
                printf '\n[WARN] Prompt timeout (%ss) — dùng mặc định: %s\n' \
                    "$_rt2_sec" "$_rt2_def" >&2
                _RT_RESULT="$_rt2_def"; printf '%s' "$_rt2_def"; return 1
            fi
            _rt2_ans=""
            if read -t "$_rt2_left" -r _rt2_ans </dev/tty 2>/dev/null; then
                _RT_RESULT="$_rt2_ans"; printf '%s' "$_rt2_ans"; return 0
            fi
            _rt2_now=$(date +%s)
            if [ $(( _rt2_now - _rt2_start )) -ge "$_rt2_sec" ]; then
                printf '\n[WARN] Prompt timeout (%ss) — dùng mặc định: %s\n' \
                    "$_rt2_sec" "$_rt2_def" >&2
                _RT_RESULT="$_rt2_def"; printf '%s' "$_rt2_def"; return 1
            fi
        done
    else
        # FIX-10-2: seed _rt2_ans="" — tránh unbound var dưới set -u.
        # FIX-10.5.1-1: thêm SIGALRM timeout thay vì block vô hạn.
        # WebUI KHÔNG bao giờ vào đây (AUTO_MODE=1 exit sớm ở trên).
        # Interactive runtime không support read -t: background subshell gửi
        # SIGALRM sau N giây. POSIX: SIGALRM thường interrupt read trên ash/dash/mksh.
        _rt2_ans=""
        ( sleep "$_rt2_sec" 2>/dev/null; kill -ALRM $$ 2>/dev/null ) &
        _rt2_bg=$!
        trap 'true' ALRM 2>/dev/null
        read -r _rt2_ans </dev/tty 2>/dev/null || true
        kill "$_rt2_bg" 2>/dev/null
        wait "$_rt2_bg" 2>/dev/null
        trap - ALRM 2>/dev/null
        if [ -z "${_rt2_ans:-}" ] && [ -n "$_rt2_def" ]; then
            printf '\n[WARN] Fallback prompt timeout (%ss) — dùng mặc định: %s\n' \
                "$_rt2_sec" "$_rt2_def" >&2
            _RT_RESULT="$_rt2_def"; printf '%s' "$_rt2_def"; return 1
        fi
        _RT_RESULT="${_rt2_ans:-$_rt2_def}"; printf '%s' "${_rt2_ans:-$_rt2_def}"
    fi
}

# ─── TIMEOUT HELPER ──────────────────────────────────────────────────
_CMD_TIMEOUT="timeout"
_HAS_TIMEOUT=0
command -v timeout >/dev/null 2>&1 && _HAS_TIMEOUT=1

if [ "$_HAS_TIMEOUT" -eq 0 ]; then
    for _to_probe in \
        /data/adb/modules/*/system/bin/timeout \
        /data/user/0/*/files/term/bin/timeout \
        /data/user/0/*/files/usr/bin/timeout; do
        # shellcheck disable=SC2231
        if [ -x "$_to_probe" ]; then
            _CMD_TIMEOUT="$_to_probe"
            _HAS_TIMEOUT=1
            break
        fi
    done
fi

_HAS_TIMEOUT_K=0
if [ "$_HAS_TIMEOUT" -eq 1 ]; then
    "$_CMD_TIMEOUT" -k 1 1 true >/dev/null 2>&1 && _HAS_TIMEOUT_K=1
fi

_run_to() {
    _rt_sec="$1"; shift
    if [ "$_HAS_TIMEOUT" -eq 1 ]; then
        if [ "$_HAS_TIMEOUT_K" -eq 1 ]; then
            "$_CMD_TIMEOUT" -k 10 "$_rt_sec" "$@"
        else
            "$_CMD_TIMEOUT" "$_rt_sec" "$@"
        fi
    else
        "$@" &
        _rt_pid=$!
        ( sleep "$_rt_sec" 2>/dev/null
          kill -0 "$_rt_pid" 2>/dev/null && kill -9 "$_rt_pid" 2>/dev/null ) &
        _rt_wpid=$!
        wait "$_rt_pid" 2>/dev/null
        _rt_ret=$?
        kill "$_rt_wpid" 2>/dev/null
        wait "$_rt_wpid" 2>/dev/null
        return "$_rt_ret"
    fi
}

# ─── DEXOPT PROGRESS RUNNER ──────────────────────────────────────────
# Spinner real elapsed/timeout (không % giả). Log snapshot mỗi 5s.
_run_dexopt() {
    _rdx_timeout="${1}"; shift
    _rdx_label="${1}";  shift
    if [ "$_HAS_TIMEOUT" -eq 1 ]; then
        if [ "$_HAS_TIMEOUT_K" -eq 1 ]; then
            "$_CMD_TIMEOUT" -k 10 "$_rdx_timeout" "$@" >/dev/null 2>&1 &
        else
            "$_CMD_TIMEOUT" "$_rdx_timeout" "$@" >/dev/null 2>&1 &
        fi
    else
        "$@" >/dev/null 2>&1 &
    fi
    _rdx_pid=$!
    _rdx_t0=$(date +%s)
    _rdx_log_t=$_rdx_t0
    _rdx_spin=0

    while kill -0 "$_rdx_pid" 2>/dev/null; do
        _rdx_now=$(date +%s)
        _rdx_el=$(( _rdx_now - _rdx_t0 ))
        # BUG-LOG-2 FIX: PID reuse guard. Sau khi timeout exit, PID có thể bị
        # tái sử dụng bởi proc khác → kill -0 luôn thành công → vòng lặp vô hạn.
        # Hard limit: timeout + 30s grace. Confirmed từ log: 362s/300s vẫn chạy.
        if [ "$_rdx_el" -gt $(( _rdx_timeout + 30 )) ]; then
            _log "  [WARN] _run_dexopt: vượt hard limit ${_rdx_el}s (max=$((  _rdx_timeout + 30 ))s) — force kill"
            kill "$_rdx_pid" 2>/dev/null
            sleep 1
            kill -9 "$_rdx_pid" 2>/dev/null
            break
        fi
        case $(( _rdx_spin % 4 )) in
            0) _rdx_c='-' ;; 1) _rdx_c='\\' ;; 2) _rdx_c='|' ;; 3) _rdx_c='/' ;;
        esac
        printf "\r  [%s] %s: %ds/%ds   " \
            "$_rdx_c" "$_rdx_label" "$_rdx_el" "$_rdx_timeout"
        _rdx_spin=$(( _rdx_spin + 1 ))
        if [ $(( _rdx_now - _rdx_log_t )) -ge 5 ]; then
            _log "  [DEXOPT] $_rdx_label — ${_rdx_el}s/${_rdx_timeout}s"
            _rdx_log_t=$_rdx_now
        fi
        sleep 2
    done

    wait "$_rdx_pid" 2>/dev/null
    _rdx_ret=$?
    _rdx_total=$(( $(date +%s) - _rdx_t0 ))
    printf "\r%-60s\r" " "   # xóa dòng spinner
    return "$_rdx_ret"
}

# ─── LOG ROTATION ────────────────────────────────────────────────────
rotate_log() {
    [ "${LOG:-/dev/null}" = "/dev/null" ] && return
    [ -f "$LOG" ] || return
    _lsz=$(size_of "$LOG")
    if [ "$_lsz" -gt "$CFG_LOG_MAX_KB" ]; then
        exec 3>&- 2>/dev/null || true
        mv "$LOG" "${LOG}.bak" 2>/dev/null
        exec 3>>"$LOG" 2>/dev/null || exec 3>/dev/null
        printf "[%s] Log rotated (%dKB)\n" "$(date +%H:%M:%S)" "$CFG_LOG_MAX_KB" >&3 2>/dev/null
    fi
}

# ─── COUNTDOWN REBOOT ────────────────────────────────────────────────
_countdown_reboot() {
    # Guard 1: lỗi trong session — block reboot
    if [ "${ERROR_COUNT:-0}" -gt 0 ]; then
        warn "[REBOOT BLOCKED] ERROR_COUNT=${ERROR_COUNT} — reboot bị huỷ vì có lỗi trong session"
        _log "[REBOOT BLOCKED] ERROR_COUNT=${ERROR_COUNT}"
        return 1
    fi
    # Guard 2: AUTO_MODE + _REBOOT_FLAG=1 → skip interactive, reboot sau 3s
    if [ "${AUTO_MODE:-0}" -eq 1 ] && [ "${_REBOOT_FLAG:-0}" -eq 1 ]; then
        _log "[AUTO-REBOOT] --reboot flag active — reboot trong 3s"
        printf "\n  [AUTO-REBOOT] Reboot trong 3s...\n"
        sleep 1; printf "  [AUTO-REBOOT] 2s...\n"
        sleep 1; printf "  [AUTO-REBOOT] 1s...\n"
        sleep 1
        reboot
        return 0
    fi
    # Guard 3: AUTO_MODE không có _REBOOT_FLAG → skip
    if [ "${AUTO_MODE:-0}" -eq 1 ]; then
        _log "[REBOOT SKIP] AUTO_MODE=1, không có --reboot flag"
        return 0
    fi

    printf '\n  [!] Reboot device? Bấm y + Enter để xác nhận, n để huỷ.\n'

    if [ "${_READ_T_OK:-0}" -eq 0 ]; then
        printf "  [WARN] Timed read không khả dụng — auto-reboot sau 20s\n"
        _crb_sec=20
        while [ "$_crb_sec" -gt 0 ]; do
            sleep 1
            _crb_sec=$((_crb_sec - 1))
        done
        reboot
        return 0
    fi

    _crb_sec=20
    while [ "$_crb_sec" -gt 0 ]; do
        printf '\r  [!] Reboot trong %3ds — y/Enter=xác nhận, n=huỷ: ' "$_crb_sec"
        _crb_in=""
        read -t 1 -r _crb_in </dev/tty 2>/dev/null || true
        case "$_crb_in" in
            y|Y)
                printf '\n'
                _log "[REBOOT] User confirmed reboot"
                reboot
                return 0
                ;;
            n|N)
                printf '\n'
                _log "[REBOOT] User cancelled reboot"
                return 2
                ;;
            *)
                ;;
        esac
        _crb_sec=$((_crb_sec - 1))
    done
    printf '\n  [!] Timeout — reboot...\n'
    _log "[REBOOT] Timeout 20s — auto reboot"
    reboot
}

# ─── CPU TEMP CHECK ──────────────────────────────────────────────────
_get_cpu_temp_hot() {
    _thresh="${1:-80}"
    _found_cpu_zone=0

    for _tz in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$_tz" ] || continue
        _tztype=""
        _tztype_file="${_tz%/temp}/type"
        [ -f "$_tztype_file" ] && read -r _tztype < "$_tztype_file" 2>/dev/null
        case "$_tztype" in
            cpu*|CPU*|tsens_tz_sensor*)
                _found_cpu_zone=1
                _t_raw=""; read -r _t_raw < "$_tz" 2>/dev/null
                case "${_t_raw:-0}" in -*) continue ;; esac
                _t=$(safe_int "${_t_raw:-0}")
                [ "$_t" -gt 1000 ] && _t=$((_t/1000))
                [ "$_t" -ge "$_thresh" ] && return 0 ;;
        esac
    done

    if [ "$_found_cpu_zone" -eq 0 ]; then
        for _tz2 in /sys/class/thermal/thermal_zone*/temp; do
            [ -f "$_tz2" ] || continue
            _t2_raw=""; read -r _t2_raw < "$_tz2" 2>/dev/null
            case "${_t2_raw:-0}" in -*) continue ;; esac
            _t2=$(safe_int "${_t2_raw:-0}")
            [ "$_t2" -gt 1000 ] && _t2=$((_t2/1000))
            [ "$_t2" -ge 90 ] && return 0
        done
    fi
    return 1
}

# ─── SAFE_RM ─────────────────────────────────────────────────────────
safe_rm() {
    for _raw in "$@"; do
        if [ -L "$_raw" ] && [ ! -e "$_raw" ]; then
            _tgt="$_raw"
            case "$_tgt" in
                /data/*|/cache/*) ;;
                *) err "[BLOCKED] dangling symlink ngoài /data,/cache: $_tgt"; continue ;;
            esac
        else
            _tgt="$(readlink -f "$_raw" 2>/dev/null)"
            if [ -z "$_tgt" ]; then
                err "[BLOCKED] canonicalize thất bại: $_raw"
                continue
            fi
        fi

        [ "${#_tgt}" -lt 8 ] && { err "[BLOCKED] Path quá ngắn: $_tgt"; continue; }

        case "$_tgt" in
            /data/adb/modules/*/remove|/data/adb/ksu/modules/*/remove|\
            /data/adb/apatch/modules/*/remove|\
            /data/adb/modules_update|\
            /data/adb/lspd/*|/data/adb/lsplant/*|\
            /data/data/*/code_cache|/data/data/*/code_cache/*|\
            /data/user_de/*/*/code_cache|/data/user_de/*/*/code_cache/*|\
            /data/misc/profiles/cur/*/*/*) ;;
            *)
                err "[BLOCKED] safe_rm ngoài allowlist: $_tgt"
                continue ;;
        esac

        # [FIX-10.5-TOCTOU] Re-resolve ngay trước khi xóa để phát hiện race condition.
        # Kẻ tấn công có thể replace thư mục bằng symlink trong khoảng thời gian
        # giữa bước check allowlist và bước rm. Kiểm tra lần hai thu hẹp window này
        # xuống gần bằng 0 trong thực tế.
        _tgt_recheck="$(readlink -f "$_raw" 2>/dev/null)"
        if [ -z "$_tgt_recheck" ] || [ "$_tgt_recheck" != "$_tgt" ]; then
            err "[BLOCKED] Path thay đổi trong lúc xử lý (TOCTOU race): $_raw"
            continue
        fi
        # Guard thêm: target canonical path không được là symlink
        if [ -L "$_tgt" ]; then
            err "[BLOCKED] Target canonical là symlink — bỏ qua để an toàn: $_tgt"
            continue
        fi

        if [ -d "$_tgt" ]; then
            # [FIX-10.5-SYMLINK] Dùng ! -type l để find không xóa qua symlink
            # bên trong thư mục. Xóa files/dirs thật trước, symlinks sau.
            find "$_tgt" -mindepth 1 -depth \( ! -type l \) -exec rm -rf {} + 2>/dev/null
            # Dọn symlinks còn lại (nếu có) — chỉ rm -f, không -rf
            find "$_tgt" -mindepth 1 -depth -type l -exec rm -f {} + 2>/dev/null
            if rmdir "$_tgt" 2>/dev/null; then
                ok "Xoá: $_tgt"
            else
                err "Xoá nội dung nhưng không rmdir được: $_tgt (SELinux?)"
            fi
        elif [ -f "$_tgt" ] || [ -L "$_tgt" ]; then
            rm -f "$_tgt" 2>/dev/null \
                && ok "Xoá: $_tgt" \
                || err "Không xoá được: $_tgt"
        else
            skip "Không tồn tại: $_tgt"
        fi
    done
}

# ─── WIPE_DIR ────────────────────────────────────────────────────────
wipe_dir() {
    _raw_dir="$1"; _desc="${2:-$1}"
    STEP=$((STEP+1))
    _prog="[${STEP}/${TOTAL_STEPS}]"

    [ -z "$_raw_dir" ] && { err "$_prog Path rỗng"; return 1; }

    if [ ! -e "$_raw_dir" ] && [ ! -L "$_raw_dir" ]; then
        _skip_quiet "$_prog SKIP (không tồn tại): $_raw_dir"
        return 0
    fi

    _dir="$(readlink -f "$_raw_dir" 2>/dev/null)"
    if [ -z "$_dir" ]; then
        err "$_prog canonicalize lỗi: $_raw_dir"
        return 1
    fi
    [ "${#_dir}" -lt 8 ] && { err "$_prog Path quá ngắn: $_dir"; return 1; }

    case "$_dir" in
        /data/vendor/ssr|/data/vendor/ssrdump|\
        /data/vendor/ramdump|/data/vendor/diag_logs|\
        /data/vendor/apanic|/data/vendor/crash_dump|\
        /data/vendor/modem_log|/data/vendor/diag|\
        /data/vendor/log|/data/vendor/log/*|\
        /data/vendor/oplus/log|/data/vendor/oplus/log/*|\
        /data/vendor/hylog|/data/vendor/hwlog|\
        /data/oppo/log|/data/oplusreserve|\
        /data/oplus/log|/data/oplus/crash|\
        /data/persist_log|\
        /data/log|/data/tombstones|/data/anr|\
        /data/system/dropbox|/data/system/heapdumps|\
        /data/system/package_cache|/data/resource-cache|/data/cache|\
        /data/user/*/*/cache|/data/user_de/*/*/cache|\
        /data/data/com.android.providers.media/cache|\
        /data/data/com.oplus.gallery3d/cache|\
        /data/data/com.coloros.filemanager/cache|\
        /data/user/0/com.oplus.engineeringmode|\
        /data/data/com.oplus.engineeringmode|\
        /data/data/com.coloros.engineeringmode|\
        /sdcard/.thumbnails|\
        /storage/emulated/*/.thumbnails|\
        /storage/emulated/*/Android/data/*/cache|\
        /data/vendor/aiengine/log|\
        /data/vendor/oplus/ai_telemetry|\
        /data/vendor/camera/debug|\
        /data/vendor/perf/trace|\
        /data/vendor/thermal/ai_thermal_log|\
        /data/vendor/coloros/log|/data/vendor/coloros/log/*|\
        /data/vendor/hyperconnect/log|/data/vendor/hyperconnect/log/*|\
        /data/vendor/oplus/ai_engine|\
        /data/vendor/ai|\
        /data/vendor/hipp/log) ;;
        *)
            err "$_prog [BLOCKED] ngoài allowlist: $_dir"
            return 1 ;;
    esac

    if [ ! -d "$_dir" ]; then
        case "$_dir" in
            /data/vendor/aiengine/*|/data/vendor/oplus/ai_telemetry|\
            /data/vendor/oplus/ai_engine|/data/vendor/ai|\
            /data/vendor/hipp/log|\
            /data/vendor/camera/debug|/data/vendor/perf/trace|\
            /data/vendor/thermal/ai_thermal_log|\
            /data/vendor/coloros/*|/data/vendor/hyperconnect/*|\
            /data/vendor/hylog|/data/vendor/hwlog|\
            /data/vendor/ssrdump|/data/vendor/ramdump|\
            /data/vendor/apanic|/data/vendor/crash_dump)
                _skip_quiet "$_prog SKIP (không phải directory): $_desc"
                return 0 ;;
        esac
        skip "$_prog SKIP (không phải directory): $_desc"
        return 0
    fi

    _probe="$(mktemp -d "${_dir}/.wipe_probe_XXXXXX" 2>/dev/null)"
    if [ -n "$_probe" ] && [ -d "$_probe" ]; then
        rmdir "$_probe" 2>/dev/null
    else
        skip "$_prog SELinux block (mktemp -d probe thất bại): $_desc"
        return 0
    fi

    if [ "${CLEAN_MEASURE_SIZE:-1}" -eq 1 ]; then
        _before=$(size_of "$_dir")
        ui "  $_prog ${_desc} — $(kb_to_mb_sh "$_before")"
    else
        # Fast mode keeps the same cleanup path and safety checks, but skips du -sk.
        if [ "${CLEAN_APP_CACHE_QUIET:-0}" -eq 1 ]; then
            _log "  $_prog [FAST] Đang xử lý: $_desc (bỏ đo dung lượng để tăng tốc)"
        else
            ui "  $_prog [FAST] ${_desc} (bỏ đo dung lượng để tăng tốc)"
        fi
    fi

    if [ "${CLEAN_APP_CACHE_QUIET:-0}" -eq 1 ]; then
        (
            while :; do
                sleep 15
                ui "  [FAST] Đang xử lý app cache..."
            done
        ) &
        _wipe_hb_pid="$!"
        find "$_dir" -mindepth 1 -maxdepth 10 ! -type d -exec rm -f {} + 2>/dev/null
        _wipe_rc=$?
        find "$_dir" -mindepth 1 -maxdepth 10 -depth -type d -empty -exec rmdir {} + 2>/dev/null
        kill "$_wipe_hb_pid" 2>/dev/null
        wait "$_wipe_hb_pid" 2>/dev/null
        if [ "$_wipe_rc" -ne 0 ]; then
            skip "Một số node trong $_desc bị SELinux chặn"
        fi
    else
        if ! find "$_dir" -mindepth 1 -maxdepth 10 ! -type d -exec rm -f {} + 2>/dev/null; then
            skip "Một số node trong $_desc bị SELinux chặn"
        fi
        find "$_dir" -mindepth 1 -maxdepth 10 -depth -type d -empty -exec rmdir {} + 2>/dev/null
    fi

    if [ "${CLEAN_MEASURE_SIZE:-1}" -eq 1 ]; then
        _after=$(size_of "$_dir")
        _freed=$((_before - _after))
        [ "$_freed" -lt 0 ] && _freed=0

        if [ "$_freed" -ge 100 ]; then
            TOTAL_FREED=$((TOTAL_FREED + _freed))
            ok "Freed: $(kb_to_mb_sh "$_freed") — $_desc"
        elif [ "$_before" -le 4 ]; then
            skip "Đã rỗng: $_desc"
        else
            _lnk_tgt="$(readlink -f "$_dir" 2>/dev/null)"
            if [ -z "$_lnk_tgt" ]; then
                warn "Symlink unreadable (transient/FUSE?): $_desc"
            else
                case "$_lnk_tgt" in
                    "$_dir"|"$_dir"/*) skip "SELinux block (freed < 100KB): $_desc" ;;
                    *) skip "SELinux block (symlink ra ngoài tree): $_desc" ;;
                esac
            fi
        fi
    else
        if [ "${CLEAN_APP_CACHE_QUIET:-0}" -eq 1 ]; then
            _log "  [OK]   [FAST] Đã xử lý: $_desc (không đo dung lượng)"
            SUCCESS_COUNT=$((SUCCESS_COUNT+1))
        else
            ok "[FAST] Đã xử lý: $_desc (bỏ đo dung lượng để tăng tốc)"
        fi
    fi
}

# ─── CLEAN TMP ───────────────────────────────────────────────────────
_clean_tmp_safe() {
    _tmpdir="$(readlink -f /data/local/tmp 2>/dev/null)"
    if [ -z "$_tmpdir" ]; then
        err "  [BLOCKED] canonicalize /data/local/tmp thất bại"
        return 1
    fi
    STEP=$((STEP+1))
    ui "  [${STEP}/${TOTAL_STEPS}] /data/local/tmp (files >1 ngày)"

    _freed_tmp=$(find "$_tmpdir" -maxdepth 1 -type f -mtime +1 \
        ! -name "CleanAce5_*.log" ! -name "orphan_*" ! -name "hooked_*" \
        ! -name "ace5_err*"       ! -name "cache_list_*" \
        ! -name "ufs_restore_*"   ! -name "lsp_scope_*" \
        -exec du -sk {} + 2>/dev/null | awk '{s+=$1} END{print s+0}')
    _freed_tmp=$(safe_int "${_freed_tmp:-0}")

    find "$_tmpdir" -maxdepth 1 -type f -mtime +1 \
        ! -name "CleanAce5_*.log" ! -name "orphan_*" ! -name "hooked_*" \
        ! -name "ace5_err*"       ! -name "cache_list_*" \
        ! -name "ufs_restore_*"   ! -name "lsp_scope_*" \
        -exec rm -f {} + 2>/dev/null

    TOTAL_FREED=$((TOTAL_FREED + _freed_tmp))
    if [ "$_freed_tmp" -gt 0 ]; then
        ok "Giải phóng /data/local/tmp: $(kb_to_mb_sh "$_freed_tmp")"
    else
        skip "Không có file rác cũ >1 ngày trong $_tmpdir"
    fi
}

# ─── SAFE_UMOUNT ─────────────────────────────────────────────────────
safe_umount() {
    _mpt_raw="$1"
    _mpt="$(readlink -f "$_mpt_raw" 2>/dev/null)"
    if [ -z "$_mpt" ]; then
        err "[BLOCKED] umount: canonicalize thất bại: $_mpt_raw"
        return 1
    fi
    case "$_mpt" in
        ""|/|/system|/vendor|/data|/dev|/proc|/sys|/apex|/mnt|/storage|\
        /product|/system_ext|/odm|/vendor_dlkm|\
        /metadata|/debug_ramdisk|/first_stage_ramdisk|/odm_dlkm)
            err "[BLOCKED] umount: $_mpt"; return 1 ;;
    esac
    [ "$ERROR_COUNT" -ge 20 ] && { err "Quá nhiều lỗi, dừng umount"; return 2; }
    # OPT-10-1: awk $2==mp field-exact thay grep -qF column-sensitive.
    # Qwen: grep false-negative nếu mount point là field cuối / có khoảng trắng.
    awk -v mp="$_mpt" '$2==mp{found=1} END{exit !found}' /proc/mounts 2>/dev/null || return 0
    umount -l "$_mpt" 2>/dev/null \
        && ok "umount: $_mpt" \
        || { err "umount thất bại: $_mpt"; return 1; }
}

# ════════════════════════════════════════════════════════════════════
#  MODULE 1 — DỌN RÁC COLOROS 15-16, QUALCOMM SM8650 & APP CACHE
# ════════════════════════════════════════════════════════════════════
mod_clean() {
    STEP=0; TOTAL_STEPS=42
    line; ui "  [1/5] Dọn rác ColorOS 15-16, Qualcomm SM8650 & App Cache"

    step "Qualcomm SM8650 Subsystem Dumps & Panic Logs"
    for _d in \
        /data/vendor/ssrdump \
        /data/vendor/ramdump \
        /data/vendor/apanic \
        /data/vendor/crash_dump
    do
        wipe_dir "$_d" "$(basename "$_d")"
    done

    step "ColorOS 15-16 / OPlus System Logs"
    for _d in \
        /data/oplus/log \
        /data/vendor/oplus/log \
        /data/vendor/modem_log \
        /data/vendor/diag \
        /data/vendor/log
    do
        wipe_dir "$_d" "$(basename "$_d")"
    done

    step "ColorOS 15-16 AI Debug, Engineering & Crash Logs"
    for _d in \
        /data/oplus/crash \
        /data/persist_log \
        /data/vendor/hylog \
        /data/vendor/hwlog \
        /data/system/heapdumps \
        /data/user/0/com.oplus.engineeringmode \
        /data/data/com.coloros.engineeringmode
    do
        wipe_dir "$_d" "$(basename "$_d")"
    done

    step "ColorOS 16 AI Telemetry & NPU Debug Logs"
    for _d in \
        /data/vendor/aiengine/log \
        /data/vendor/oplus/ai_telemetry \
        /data/vendor/camera/debug \
        /data/vendor/perf/trace \
        /data/vendor/thermal/ai_thermal_log \
        /data/vendor/oplus/ai_engine \
        /data/vendor/ai \
        /data/vendor/hipp/log
    do
        wipe_dir "$_d" "$(basename "$_d")"
    done

    step "Legacy ColorOS Log Paths (older ROM variants)"
    for _d in \
        /data/vendor/coloros/log \
        /data/vendor/hyperconnect/log
    do
        wipe_dir "$_d" "$(basename "$(dirname "$_d")")/$(basename "$_d")"
    done

    step "Android System Logs"
    for _d in \
        /data/log \
        /data/tombstones \
        /data/anr \
        /data/system/dropbox
    do
        wipe_dir "$_d" "$(basename "$_d")"
    done

    step "App Cache (All Users)"
    if [ "${CLEAN_FAST_MODE:-0}" -eq 1 ]; then
        ui "  [FAST] Bỏ qua quét cache từng app để tăng tốc. Dùng Dọn toàn bộ để quét sâu."
        _appcache_fixed=0
        CLEAN_APP_CACHE_QUIET=1
        for _pcache in \
            /data/data/com.android.providers.media/cache \
            /data/data/com.android.vending/cache \
            /data/data/com.google.android.gms/cache
        do
            [ -d "$_pcache" ] || continue
            wipe_dir "$_pcache" "$(basename "$(dirname "$_pcache")")/cache"
            _appcache_fixed=$((_appcache_fixed+1))
        done
        CLEAN_APP_CACHE_QUIET=0
        ok "App cache fast mode: skipped full scan; fixed_paths=${_appcache_fixed}"
    else
        _cache_list="$(mktemp /data/local/tmp/cache_list_XXXXXX 2>/dev/null)"
        if [ -n "$_cache_list" ]; then
            find /data/user /data/user_de \
                -mindepth 2 -maxdepth 3 -type d -name "cache" \
                2>/dev/null > "$_cache_list"
            _appcache_count=0
            while IFS= read -r _cline; do
                [ -n "$_cline" ] && _appcache_count=$((_appcache_count+1))
            done < "$_cache_list"
            TOTAL_STEPS=$((TOTAL_STEPS + _appcache_count))
            _appcache_processed=0
            while IFS= read -r _pcache; do
                [ -d "$_pcache" ] || continue
                wipe_dir "$_pcache" "$(basename "$(dirname "$_pcache")")/cache"
                _appcache_processed=$((_appcache_processed+1))
            done < "$_cache_list"
            rm -f "$_cache_list" 2>/dev/null
        else
            warn "mktemp thất bại — dùng fallback 2-pass cho app cache"
            _appcache_count=0
            for _udir in /data/user/* /data/user_de/*; do
                [ -d "$_udir" ] || continue
                for _pcache in "$_udir"/*/cache; do
                    [ -d "$_pcache" ] && _appcache_count=$((_appcache_count+1))
                done
            done
            TOTAL_STEPS=$((TOTAL_STEPS+_appcache_count))
            _appcache_processed=0
            for _udir in /data/user/* /data/user_de/*; do
                [ -d "$_udir" ] || continue
                for _pcache in "$_udir"/*/cache; do
                    [ -d "$_pcache" ] || continue
                    wipe_dir "$_pcache" "$(basename "$(dirname "$_pcache")")/cache"
                    _appcache_processed=$((_appcache_processed+1))
                done
            done
        fi
    fi

    step "Media Cache"
    for _d in \
        /data/data/com.android.providers.media/cache \
        /sdcard/.thumbnails
    do
        wipe_dir "$_d" "$(basename "$_d")"
    done

    step "Media Cache FUSE — Dynamic Resolver"
    _fuse_installed_pkgs="$(pm list packages 2>/dev/null || true)"
    for _fpkg in \
        com.oplus.gallery3d \
        com.coloros.gallery3d \
        com.oplus.photos \
        com.coloros.photos \
        com.coloros.filemanager
    do
        STEP=$((STEP+1)); _prog="[${STEP}/${TOTAL_STEPS}]"
        ui "  $_prog FUSE cache: $_fpkg"
        case "$_fuse_installed_pkgs" in
            *"package:${_fpkg}"*) ;;
            *)
                skip "Không cài: $_fpkg"
                continue ;;
        esac
        if [ "$_SDK" -ge 33 ] && command -v cmd >/dev/null 2>&1 && \
           cmd package trim-cache "$_fpkg" >/dev/null 2>&1; then
            ok "cmd trim-cache (SDK 33+): $_fpkg"
        elif [ "$_SDK" -ge 26 ] && command -v pm >/dev/null 2>&1 && \
           pm clear --cache-only "$_fpkg" >/dev/null 2>&1; then
            ok "pm clear --cache-only: $_fpkg"
        else
            skip "Không clear được FUSE cache: $_fpkg (SDK $_SDK)"
        fi
    done
    unset _fuse_installed_pkgs

    step "System / Temp Cache"
    for _d in \
        /data/system/package_cache \
        /data/resource-cache \
        /data/cache
    do
        wipe_dir "$_d" "$(basename "$_d")"
    done
    _clean_tmp_safe

    STEP=$((STEP+1))
    ui "  [${STEP}/${TOTAL_STEPS}] Overlay *.cache"
    _oc_freed=0
    for _ocp_raw in /data/system/overlays /data/oplus; do
        case "$_ocp_raw" in
            /data/system/overlays|/data/oplus) ;;
            *) err "[BLOCKED] overlay cache: path ngoài allowlist: $_ocp_raw"; continue ;;
        esac
        _ocp="$(readlink -f "$_ocp_raw" 2>/dev/null)"
        if [ -z "$_ocp" ]; then
            err "[BLOCKED] canonicalize thất bại: $_ocp_raw"
            continue
        fi
        [ -d "$_ocp" ] || continue
        _oc_chunk=$(find "$_ocp" -maxdepth 1 -name "*.cache" -type f \
            -exec du -sk {} + 2>/dev/null | awk '{s+=$1} END{print s+0}')
        _oc_freed=$(( _oc_freed + $(safe_int "${_oc_chunk:-0}") ))
        find "$_ocp" -maxdepth 1 -name "*.cache" -type f \
            -exec rm -f {} + 2>/dev/null
    done
    [ "$_oc_freed" -gt 0 ] && {
        TOTAL_FREED=$((TOTAL_FREED+_oc_freed))
        ok "Overlay cache: $(kb_to_mb_sh "$_oc_freed")"
    } || skip "Không có overlay *.cache"

    line; ok "Hoàn tất dọn rác ColorOS 15-16 & Qualcomm SM8650"
    rotate_log
}

# ════════════════════════════════════════════════════════════════════
#  MODULE 2 — TỐI ƯU MODULE KSU/MAGISK/APATCH & LSPOSED
# ════════════════════════════════════════════════════════════════════
mod_modules() {
    STEP=0; TOTAL_STEPS=10
    line; ui "  [2/5] Tối ưu Module KSU/Magisk/APatch & LSPosed"

    step "Quét Orphan Modules (KSU/Magisk/APatch)"
    _mod_count=0; _orphan_count=0
    for _base in /data/adb/modules /data/adb/ksu/modules /data/adb/apatch/modules; do
        [ -d "$_base" ] || continue
        while IFS= read -r _mdir || [ -n "$_mdir" ]; do
            [ -d "$_mdir" ] || continue
            _mod_count=$((_mod_count+1))
            _mid="${_mdir##*/}"
            if [ "$_mid" = "TA_utl" ] || [ "$_mdir" = "/data/adb/modules/TA_utl" ]; then
                skip "Whitelisted module: $_mdir"
                continue
            fi
            if [ ! -f "${_mdir}/module.prop" ] && [ ! -f "${_mdir}/update" ]; then
                warn "Orphan candidate: $_mdir"
                printf "%s\n" "$_mdir" >> "$ORPHAN_TMP"
                _orphan_count=$((_orphan_count+1))
            fi
        done <<OREOF
$(find "$_base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
OREOF
    done
    ui "  Đã quét: ${_mod_count} modules | Orphan candidates: ${_orphan_count}"

    if [ -s "$ORPHAN_TMP" ]; then
        ui "  Danh sách orphan:"
        while IFS= read -r _op; do [ -n "$_op" ] && ui "    -> $_op"; done < "$ORPHAN_TMP"
        printf "  Xoá orphan modules? (y/n, 60s timeout): "
        _read_timed 60 n; _yn="$_RT_RESULT"
        if [ "${_yn:-n}" = "y" ]; then
            while IFS= read -r _op; do
                [ -n "$_op" ] || continue
                _op_c="$(readlink -f "$_op" 2>/dev/null)"
                case "${_op_c:-}" in
                    /data/adb/modules/*|\
                    /data/adb/ksu/modules/*|\
                    /data/adb/apatch/modules/*)
                        _op_verify="$(readlink -f "$_op" 2>/dev/null)"
                        if [ "${_op_verify:-}" != "$_op_c" ]; then
                            err "TOCTOU detected: '$_op' — bỏ qua"
                            continue
                        fi
                        # BUG-9.3-2 FIX (v9.4.1): rm -rf xoá đệ quy subdirs
                        # (system/lib64/ etc.). Không dùng -delete (non-POSIX).
                        find "$_op_c" -mindepth 1 -depth -exec rm -rf {} + 2>/dev/null
                        rmdir "$_op_c" 2>/dev/null \
                            && ok "Orphan xoá: $_op_c" \
                            || err "Orphan rmdir thất bại: $_op_c (SELinux?)"
                        ;;
                    *)
                        err "[BLOCKED] Orphan path ngoài module tree: ${_op_c:-$_op}"
                        ;;
                esac
            done < "$ORPHAN_TMP"
            : > "$ORPHAN_TMP"; ok "Orphan modules đã xoá"
        else
            skip "Bỏ qua orphan"
        fi
    fi

    if [ -d "/data/adb/modules_update" ]; then
        _fresh=$(find /data/adb/modules_update -mindepth 1 -mtime -1 2>/dev/null | head -n 1)
        if [ -n "$_fresh" ]; then
            warn "modules_update có pending update hợp lệ (<24h) — BỎ QUA reset"
        else
            safe_rm /data/adb/modules_update
            mkdir -p /data/adb/modules_update 2>/dev/null && ok "Reset modules_update"
        fi
    fi

    step "Stale Mount Cleanup"
    _mdata="$(grep -E '(/data/adb/modules/|/data/adb/ksu/modules/|/data/adb/apatch/modules/)' \
        /proc/mounts 2>/dev/null || true)"

    if [ -n "$_mdata" ]; then
        _stale_found=0
        while IFS= read -r _mline; do
            [ -z "$_mline" ] && continue
            _mp="${_mline#* }"; _mp="${_mp%% *}"
            [ -z "$_mp" ] && continue
            _rel="${_mline#*modules/}"; _mname="${_rel%%/*}"
            if [ -n "$_mname" ] && \
               [ ! -d "/data/adb/modules/$_mname" ] && \
               [ ! -d "/data/adb/ksu/modules/$_mname" ] && \
               [ ! -d "/data/adb/apatch/modules/$_mname" ]; then
                warn "Stale mount '$_mname': $_mp"
                safe_umount "$_mp"
                _src=$?
                [ "$_src" -eq 2 ] && { err "Quá nhiều lỗi — dừng umount"; break; }
                _stale_found=$((_stale_found+1))
            fi
        done <<MEOF
$_mdata
MEOF
        [ "$_stale_found" -eq 0 ] && ok "Scan stale mounts: OK — 0 stale"
    else
        skip "Không có stale module mounts"
    fi

    _has_lsp=0; _lsp_base=""; _lsp_config=""
    for _lp in /data/adb/lspd /data/adb/lsplant; do
        if [ -d "$_lp" ]; then
            _has_lsp=1; _lsp_base="$_lp"
            [ -d "$_lp/config" ] && _lsp_config="$_lp/config"
            break
        fi
    done

    if [ "$_has_lsp" -eq 1 ]; then
        step "LSPosed/LSPlant Cache & Dehook ($_lsp_base)"

        if [ -z "$HOOKED_TMP" ]; then
            HOOKED_TMP="$(mktemp /data/local/tmp/hooked_XXXXXX 2>/dev/null)" || {
                err "mktemp HOOKED_TMP thất bại — bỏ qua LSPosed"
                _has_lsp=0
            }
        fi

        if [ "$_has_lsp" -eq 1 ]; then
            safe_rm "$_lsp_base/log" "$_lsp_base/cache"

            : > "$HOOKED_TMP"
            if [ -n "$_lsp_config" ]; then
                _lsp_scope_tmp="$(mktemp /data/local/tmp/lsp_scope_XXXXXX 2>/dev/null)"
                if [ -n "$_lsp_scope_tmp" ]; then
                    cat "$_lsp_config"/*/scope > "$_lsp_scope_tmp" 2>/dev/null || true
                    while IFS= read -r _sp_line || [ -n "$_sp_line" ]; do
                        [ -z "$_sp_line" ] && continue
                        case "$_sp_line" in
                            android|system_server) continue ;;
                        esac
                        grep -qF "$_sp_line" "$HOOKED_TMP" 2>/dev/null || \
                            printf '%s\n' "$_sp_line" >> "$HOOKED_TMP"
                    done < "$_lsp_scope_tmp"
                    rm -f "$_lsp_scope_tmp" 2>/dev/null
                else
                    if command -v awk >/dev/null 2>&1; then
                        awk '!seen[$0]++ && $0 !~ /^(android|system_server)$/ {print}' \
                            "$_lsp_config"/*/scope 2>/dev/null > "$HOOKED_TMP" || true
                    fi
                fi
            fi

            if [ ! -s "$HOOKED_TMP" ]; then
                warn "Không đọc được scope config — dùng fallback"
                warn "CẢNH BÁO: Sẽ Full AOT compile systemui (~2-3 phút)"
                printf "  Tiếp tục compile systemui trong fallback? (y/n, 60s): "
                _read_timed 60 n; _fbyn="$_RT_RESULT"
                if [ "${_fbyn:-n}" = "y" ]; then
                    _launcher="$(cmd package resolve-activity --brief \
                        android.intent.action.MAIN android.intent.category.HOME 2>/dev/null \
                        | tr -d '\033' | sed -n 's/^\([a-z][a-zA-Z0-9._]*\).*/\1/p' | head -n 1)"
                    {
                        printf "com.android.systemui\ncom.android.settings\n"
                        [ -n "$_launcher" ] && printf "%s\n" "$_launcher"
                    } > "$HOOKED_TMP"
                else
                    skip "Bỏ qua LSPosed fallback compile"
                fi
            fi

            if _get_cpu_temp_hot 80; then
                warn "CPU đang nóng (≥80°C) — đợi 5s"
                sleep 5
            fi

            _can_compile=0
            if [ "$_SDK" -ge 24 ]; then
                _can_compile=1
            else
                warn "SDK $_SDK < 24 — bỏ qua compile"
            fi

            if [ "$_can_compile" -eq 1 ]; then
                _avkb_data="$(df -k /data 2>/dev/null | \
                    { read _dfh; read _dfd _dfsz _dfu _dfav _dfr; \
                      printf '%s' "${_dfav:-0}"; })"
                _avkb_data="$(safe_int "${_avkb_data:-0}")"
                if [ "$_avkb_data" -lt 102400 ]; then
                    warn "Không đủ dung lượng /data (<100MB) — bỏ toàn bộ recompile"
                    _can_compile=0
                fi
            fi

            _has_pm_art=0
            if command -v pm >/dev/null 2>&1 && pm art help >/dev/null 2>&1; then
                _has_pm_art=1
            fi

            _MAX_COMPILE_PKG=10
            _dhcount=0
            _compile_count=0

            while IFS= read -r _pkg || [ -n "$_pkg" ]; do
                [ -z "$_pkg" ] && continue
                if ! _is_valid_pkg "$_pkg"; then
                    warn "Bỏ qua package tên không hợp lệ: $_pkg"
                    continue
                fi
                [ -d "/data/data/$_pkg" ] || continue
                step "Dehook: $_pkg"

                if command -v am >/dev/null 2>&1; then
                    am force-stop "$_pkg" >/dev/null 2>&1 \
                        && ok "Force-stopped: $_pkg" \
                        || warn "Force-stop thất bại: $_pkg"
                else
                    warn "am không tìm thấy — bỏ qua force-stop: $_pkg"
                fi

                safe_rm "/data/data/$_pkg/code_cache" \
                        "/data/user_de/0/$_pkg/code_cache"

                _prof="/data/misc/profiles/cur/0/$_pkg/primary.prof"
                if [ "$_has_pm_art" -eq 1 ] && [ "$_SDK" -ge 35 ]; then
                    pm art clear-app-profiles "$_pkg" >/dev/null 2>&1 \
                        && ok "pm art clear-app-profiles: $_pkg" \
                        || {
                            [ -f "$_prof" ] && rm -f "$_prof" 2>/dev/null \
                                && ok "ART profile cleared (rm fallback): $_pkg" \
                                || warn "Không clear được profile: $_pkg"
                        }
                else
                    [ -f "$_prof" ] && rm -f "$_prof" 2>/dev/null \
                        && ok "ART profile cleared: $_pkg" \
                        || true
                fi

                if [ "$_can_compile" -eq 1 ]; then
                    mkdir -p "/data/data/$_pkg/code_cache" 2>/dev/null
                    if [ "$_compile_count" -ge "$_MAX_COMPILE_PKG" ]; then
                        warn "Đạt giới hạn ${_MAX_COMPILE_PKG} compile — bỏ qua: $_pkg"
                    else
                        if [ "$_compile_count" -gt 0 ]; then
                            if _get_cpu_temp_hot 80; then
                                warn "CPU quá nhiệt (≥80°C) — đợi 5s: $_pkg"
                                sleep 5
                            else
                                sleep 1
                            fi
                        fi
                        ui "  [${_compile_count}/${_MAX_COMPILE_PKG}] Recompile (90s): $_pkg"
                        if [ "$_has_pm_art" -eq 1 ] && [ "$_SDK" -ge 35 ]; then
                            _run_to 90 pm compile -m speed-profile -f "$_pkg" >/dev/null 2>&1 \
                                && ok "Recompiled (pm compile speed-profile): $_pkg" \
                                || err "Recompile thất bại/timeout: $_pkg"
                        else
                            _run_to 90 cmd package compile -m speed-profile -f "$_pkg" >/dev/null 2>&1 \
                                && ok "Recompiled (cmd package compile speed-profile): $_pkg" \
                                || err "Recompile thất bại/timeout: $_pkg"
                        fi
                        _compile_count=$((_compile_count+1))
                    fi
                fi
                _dhcount=$((_dhcount+1))
            done < "$HOOKED_TMP"

            ui "  Dehooked: ${_dhcount} packages"
        fi
    else
        skip "LSPosed/LSPlant không phát hiện"
    fi

    line; ok "Hoàn tất tối ưu Module"
    rotate_log
}

# ════════════════════════════════════════════════════════════════════
#  MODULE 3 — SMART BOOST: DROP CACHES + COMPACT RAM + FSTRIM UFS 4.0
# ════════════════════════════════════════════════════════════════════
mod_boost() {
    line; ui "  [3/5] Smart Boost (Drop Cache, Logcat, Compact RAM, FSTRIM UFS 4.0)"

    step "Trim Memory (Freezer v4 Compatible)"
    warn "Sẽ signal trim app nền — download/sync có thể bị gián đoạt"
    if command -v cmd >/dev/null 2>&1; then
        cmd activity idle-maintenance >/dev/null 2>&1 \
            && ok "Idle maintenance triggered (Freezer v4 safe)" \
            || warn "idle-maintenance không phản hồi — bỏ qua (KILL-SOFTEN)"
    else
        warn "cmd không tìm thấy — bỏ qua trim memory step"
    fi
    sync; ok "I/O buffers synced"

    if [ "$_SDK" -ge 35 ]; then
        skip "SDK $_SDK ≥ 35: send-trim-memory deprecated"
    else
        if [ "$_SDK" -ge 21 ] && command -v am >/dev/null 2>&1; then
            am send-trim-memory system_server RUNNING_LOW >/dev/null 2>&1 \
                && ok "Trim RUNNING_LOW: system_server" \
                || warn "send-trim-memory system_server thất bại"
            am send-trim-memory surfaceflinger HIDDEN >/dev/null 2>&1 \
                && ok "Trim HIDDEN: surfaceflinger" \
                || warn "send-trim-memory surfaceflinger thất bại"
        fi
        if [ "$_SDK" -ge 26 ] && command -v am >/dev/null 2>&1; then
            am send-trim-memory all BACKGROUND >/dev/null 2>&1 \
                && ok "Trim BACKGROUND: all background apps" \
                || warn "send-trim-memory all thất bại"
        elif [ "$_SDK" -ge 21 ]; then
            skip "SDK $_SDK < 26 — bỏ qua send-trim-memory all"
        fi
    fi

    step "Drop PageCache + Logcat Ring Buffer (LPDDR5X Safe)"
    _uptime_days=0
    if [ -f /proc/uptime ]; then
        read -r _upt _upi < /proc/uptime 2>/dev/null || true
        _upt="${_upt%%.*}"
        _upt=$(safe_int "${_upt:-0}")
        [ "$_upt" -gt 0 ] 2>/dev/null && _uptime_days=$(( _upt / 86400 ))
    fi
    _drop_level=1
    ui "  Uptime: ${_uptime_days} ngày"
    if [ "$_uptime_days" -ge 15 ]; then
        warn "Uptime > 15 ngày — giữ Level 1 (Level 2 gây stutter ColorOS UI)"
    fi
    printf '%s\n' "$_drop_level" > /proc/sys/vm/drop_caches 2>/dev/null \
        && ok "Level ${_drop_level}: drop_caches OK" \
        || err "drop_caches bị chặn (level ${_drop_level})"
    _fkb=$(get_ram_kb); ui "  RAM sau drop_caches: $(kb_to_mb_sh "$_fkb")"

    if command -v logcat >/dev/null 2>&1; then
        logcat -b all -c 2>/dev/null \
            && ok "Logcat ring buffers cleared (main/system/crash/radio/events/kernel)" \
            || warn "logcat -b all -c thất bại — SELinux? Bỏ qua."
    else
        skip "logcat binary không tìm thấy"
    fi
    _fkb2=$(get_ram_kb); ui "  RAM sau logcat clear: $(kb_to_mb_sh "$_fkb2")"

    step "Memory Compaction & LPDDR5X Tuning (SM8650)"
    _did_compact=0
    if [ -f /proc/sys/vm/watermark_boost_factor ] && \
       [ -f /proc/sys/vm/watermark_scale_factor ]; then

        printf '%s\n' '0' > /proc/sys/vm/watermark_boost_factor  2>/dev/null
        # HW-10-1: 250 → 150. 250 gây kswapd wake-up liên tục trên LPDDR5X 12GB
        # (UI stutter). 150 = ngưỡng kcompactd an toàn (Qwen + Gemini + Lead Dev).
        printf '%s\n' '150' > /proc/sys/vm/watermark_scale_factor  2>/dev/null
        ok "kcompactd trigger: scale=150 (LPDDR5X kswapd safe), boost=0"
        _did_compact=1
        # SEC-10-1: vfs_cache_pressure=150 ĐÃ BỊ XÓA.
        # Qwen + Gemini: phá AI memory forecast ColorOS 15/16, tăng cold-start latency
        # do inode/dentry cache bị reclaim sớm. Android tự quản lý VFS cache tốt hơn.

        sleep 3

        if [ -n "${_WMK_SCALE_ORIG+set}" ] && [ -n "$_WMK_SCALE_ORIG" ] && \
           [ -f /proc/sys/vm/watermark_scale_factor ]; then
            _wmk_inline="$(printf '%s' "$_WMK_SCALE_ORIG" | tr -cd '0-9')"
            if [ -n "$_wmk_inline" ]; then
                printf '%s\n' "$_wmk_inline" > /proc/sys/vm/watermark_scale_factor 2>/dev/null \
                    && ok "watermark_scale_factor restored: ${_WMK_SCALE_ORIG}" \
                    || warn "Không restore được watermark_scale_factor"
            fi
        fi

        if [ -n "${_VFS_CACHE_ORIG+set}" ] && [ -n "$_VFS_CACHE_ORIG" ] && \
           [ -f /proc/sys/vm/vfs_cache_pressure ]; then
            _vfs_inline="$(printf '%s' "$_VFS_CACHE_ORIG" | tr -cd '0-9')"
            if [ -n "$_vfs_inline" ]; then
                printf '%s\n' "$_vfs_inline" > /proc/sys/vm/vfs_cache_pressure 2>/dev/null \
                    && ok "vfs_cache_pressure restored: ${_VFS_CACHE_ORIG}" \
                    || warn "Không restore được vfs_cache_pressure"
            fi
        fi

        if [ -n "${_WMK_BOOST_ORIG+set}" ] && [ -n "$_WMK_BOOST_ORIG" ] && \
           [ -f /proc/sys/vm/watermark_boost_factor ]; then
            _wmb_inline="$(printf '%s' "$_WMK_BOOST_ORIG" | tr -cd '0-9')"
            if [ -n "$_wmb_inline" ]; then
                printf '%s\n' "$_wmb_inline" > /proc/sys/vm/watermark_boost_factor 2>/dev/null \
                    && ok "watermark_boost_factor restored: ${_WMK_BOOST_ORIG}" \
                    || warn "Không restore được watermark_boost_factor"
            fi
        else
            printf '%s\n' '0' > /proc/sys/vm/watermark_boost_factor 2>/dev/null
        fi
    fi

    if [ "$_did_compact" -eq 0 ] && [ -f /proc/sys/vm/compact_memory ]; then
        (printf '%s\n' '1' > /proc/sys/vm/compact_memory 2>/dev/null &)
        ok "compact_memory triggered (background fallback)"
        _did_compact=1
    fi
    [ "$_did_compact" -eq 0 ] && warn "Không có sysfs compaction khả dụng"

    step "UFS 4.0 Queue Tuning (SM8650 Native)"
    _ufs_tuned=0
    for _blk in /sys/block/sd[a-f]; do
        [ -d "$_blk/queue" ] || continue
        _ufs_write_ok=0
        _ufs_applied=""
        if [ -f "$_blk/queue/iostats" ]; then
            _ufs_v_orig="$(cat "$_blk/queue/iostats" 2>/dev/null)"
            if printf '%s\n' '0' > "$_blk/queue/iostats" 2>/dev/null; then
                [ -n "${_UFS_RESTORE_TMP:-}" ] && \
                    printf '%s:iostats:%s\n' "$_blk" "${_ufs_v_orig:-0}" \
                    >> "$_UFS_RESTORE_TMP" 2>/dev/null
                _ufs_write_ok=1
                _ufs_applied="${_ufs_applied:+${_ufs_applied},}iostats=0(orig=${_ufs_v_orig:-?})"
            else
                warn "UFS sysfs deny: $_blk/queue/iostats"
            fi
        fi
        # HW-10-2: nr_requests=128 và read_ahead_kb=256 ĐÃ BỊ XÓA.
        # SM8650 dùng blk-mq + mq-deadline + HPB tự quản lý động I/O scheduling.
        # Static override phá luồng native của UFS 4.0 (Qwen + Gemini xác nhận).
        # Chỉ giữ iostats=0 (tắt I/O stat accounting, không ảnh hưởng scheduling).
        if [ "$_ufs_write_ok" -eq 1 ]; then
            ok "UFS queue tuned: $_blk ($_ufs_applied)"
            _ufs_tuned=$((_ufs_tuned+1))
        else
            warn "UFS queue: $_blk không write được sysfs nào"
        fi
    done
    [ "$_ufs_tuned" -eq 0 ] && skip "Không tìm thấy block device UFS có thể tune"

    step "FSTRIM UFS 4.0 (RW Partitions Only)"
    if [ "$_SDK" -ge 36 ]; then
        sm fstrim >/dev/null 2>&1 \
            && ok "sm fstrim (SDK 36 primary)" \
            || warn "sm fstrim thất bại (SDK 36)"
    else
        for _mp in /data /cache /metadata /mnt/user/0; do
            if grep -qF " $_mp " /proc/mounts 2>/dev/null; then
                fstrim -v "$_mp" >/dev/null 2>&1 \
                    && ok "Trimmed: $_mp" \
                    || {
                        if [ "$_SDK" -ge 33 ]; then
                            skip "Direct fstrim kernel-blocked (SDK $_SDK)"
                        else
                            warn "fstrim $_mp thất bại"
                        fi
                    }
            fi
        done
        if [ "$_SDK" -ge 33 ]; then
            cmd storage fstrim >/dev/null 2>&1 \
                && ok "StorageManager FSTRIM (cmd storage fstrim)" \
                || {
                    sm fstrim >/dev/null 2>&1 \
                        && ok "StorageManager FSTRIM (sm fallback)" \
                        || warn "StorageManager FSTRIM thất bại"
                }
        else
            sm fstrim >/dev/null 2>&1 \
                && ok "StorageManager FSTRIM" \
                || warn "sm fstrim thất bại (SDK $_SDK)"
        fi
    fi

    sync
    ok "Post-fstrim sync barrier hoàn tất"
    ui "  [INFO] Post-fstrim settle 5s (UFS async TRIM flush)..."
    sleep 5

    line; ok "Hoàn tất Smart Boost"
    rotate_log
}

# ════ MODULE 3b — NETWORK RESET ════
mod_network_reset() {
    line; ui "  [3b/5+] Network Reset (WiFi / Data / DNS)"

    step "Flush DNS Cache"
    if command -v ndc >/dev/null 2>&1; then
        if ndc resolver flushdefaultif >/dev/null 2>&1; then
            ok "ndc resolver flushdefaultif hoàn tất"
            _log "DNS flush: ndc resolver flushdefaultif OK"
        else
            warn "ndc resolver flushdefaultif thất bại (SELinux?) — thử fallback"
            _log "DNS flush: ndc fail, thử cmd connectivity"
            cmd connectivity flush-default-dns >/dev/null 2>&1 || true
            _log "DNS flush: cmd connectivity fallback done"
        fi
    else
        _log "DNS flush: ndc không có — thử cmd connectivity"
        cmd connectivity flush-default-dns >/dev/null 2>&1 || true
        ok "cmd connectivity flush-default-dns (fallback)"
    fi

    step "WiFi Reset"
    _run_to 5 svc wifi disable >/dev/null 2>&1 && ok "WiFi disabled" || warn "WiFi disable thất bại (timeout/fail)"
    # [FIX-10.5-NET] Tăng từ 1s → 3s để firmware WiFi SM8650 có đủ thời gian
    # shutdown thật sự ở tầng driver, không chỉ tắt ở Framework layer.
    sleep 3
    _run_to 5 svc wifi enable >/dev/null 2>&1 && ok "WiFi enabled" || warn "WiFi enable thất bại (timeout/fail)"

    step "Mobile Data Reset"
    _run_to 5 svc data disable >/dev/null 2>&1 && ok "Data disabled" || warn "Data disable thất bại (timeout/fail)"
    sleep 3
    _run_to 5 svc data enable >/dev/null 2>&1 && ok "Data enabled" || warn "Data enable thất bại (timeout/fail)"

    step "Netd Resolver State Flush"
    if command -v ndc >/dev/null 2>&1; then
        ndc resolver clearnetdns >/dev/null 2>&1 || true
        _log "ndc resolver clearnetdns done (no-op nếu SELinux block)"
        ok "ndc resolver clearnetdns"
    else
        _log "ndc không có — skip clearnetdns"
        warn "ndc không khả dụng — bỏ qua clearnetdns"
    fi

    line; ok "Hoàn tất Network Reset"
    rotate_log
}

# ════════════════════════════════════════════════════════════════════
#  MODULE 4 — REBUILD ART/DALVIK — APEX SAFE (Android 15-16)
# ════════════════════════════════════════════════════════════════════
mod_dalvik() {
    line; ui "  [4/5] Rebuild ART/Dalvik (APEX Safe — Android 15-16 / SDK 35-36)"

    warn "Dùng native ART API — an toàn với APEX (không bootloop)"
    warn "Thời gian ước tính: 2-5 phút | Máy có thể ấm hơn"
    warn "Khuyến nghị: Pin > 30% trước khi thực hiện"

    renice 19 $$ >/dev/null 2>&1 || true
    ionice -c 2 -n 7 -p $$ 2>/dev/null || true

    if [ "$_SDK" -lt 31 ] && [ "$_SDK" -ne 0 ]; then
        warn "SDK $_SDK < 31 — script thiết kế cho Android 15-16 / SDK 35-36"
        printf "  Tiếp tục với rủi ro? (y/n, 60s): "
        _read_timed 60 n; _sdkwarn="$_RT_RESULT"
        case "${_sdkwarn:-n}" in y|Y) ;; *) skip "Huỷ — SDK không đúng target"; return 0 ;; esac
    fi

    _batt=""
    [ -f /sys/class/power_supply/battery/capacity ] && \
        _batt="$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
    if [ -z "$_batt" ] || [ "$(safe_int "$_batt")" -eq 0 ]; then
        _batt="$(dumpsys battery 2>/dev/null | \
            sed -n 's/.*level: *\([0-9][0-9]*\).*/\1/p' | head -n 1)"
    fi
    _batt=$(safe_int "$_batt")
    if [ -z "$_batt" ] || [ "$_batt" -eq 0 ]; then
        warn "Không đọc được mức pin"
        printf "  Nhập mức pin (%%) hoặc Enter để bỏ qua (30s): "
        _read_timed 30 0; _manual="$_RT_RESULT"
        _batt=$(safe_int "${_manual:-0}")
    fi

    _is_charging=0
    _chg_raw="$(dumpsys battery 2>/dev/null | grep -E 'powered:|status:' | head -4)"
    case "$_chg_raw" in
        *"AC powered: true"*|*"USB powered: true"*|*"Wireless powered: true"*)
            _is_charging=1 ;;
    esac
    if [ -z "$_chg_raw" ] && [ -f /sys/class/power_supply/battery/status ]; then
        _chg_sysfs="$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
        case "$_chg_sysfs" in Charging|Full) _is_charging=1 ;; esac
    fi
    if [ "$_is_charging" -eq 1 ]; then
        ok "Đang sạc — điều kiện tốt nhất để rebuild ART"
    else
        warn "Không sạc — pin: ${_batt}%"
        if [ "$_batt" -lt 30 ] && [ "$_batt" -gt 0 ]; then
            warn "Pin thấp (<30%) — dexopt có thể rollback"
            printf "  Tiếp tục bất chấp pin thấp? (y/n, 30s): "
            _read_timed 30 n; _lowbatt="$_RT_RESULT"
            case "${_lowbatt:-n}" in y|Y) ;; *) skip "Huỷ — pin thấp"; return 0 ;; esac
        fi
    fi

    _thermal_safe=1
    # HW-10-3: 70 → 65°C. Athena throttle bắt đầu từ 72°C; 7°C margin an toàn.
    # Qwen override CHATGPT PASS theo Safety priority (POSIX > Safety > HW).
    if _get_cpu_temp_hot 65; then
        warn "CPU ≥65°C — chờ nguội 10s"
        sleep 10
        if _get_cpu_temp_hot 65; then
            warn "CPU vẫn nóng ≥65°C — KHÔNG kích hoạt thermal bypass"
            _thermal_safe=0
        fi
    fi

    _has_pm_art=0
    command -v pm >/dev/null 2>&1 && pm art help >/dev/null 2>&1 && _has_pm_art=1

    _thermal_bypassed=0
    if [ "$_thermal_safe" -eq 1 ] && [ "$_SDK" -ge 33 ] && command -v cmd >/dev/null 2>&1; then
        cmd thermalservice override-status 0 >/dev/null 2>&1 \
            && { _thermal_bypassed=1; printf '%s\n' "$(date +%s 2>/dev/null)" > "$_THERM_DPM_FLAG" 2>/dev/null; ok "Thermal DPM bypass: override-status 0"; } \
            || warn "Thermal override không khả dụng"
    fi

    step "ART Cleanup (profiles + code_cache)"
    if [ "$_has_pm_art" -eq 1 ] && [ "$_SDK" -ge 35 ]; then
        _run_to 120 pm art cleanup >/dev/null 2>&1 \
            && ok "pm art cleanup (SDK 35+)" \
            || warn "pm art cleanup thất bại/timeout"
    else
        warn "pm art không khả dụng (pm_art=${_has_pm_art}, SDK=${_SDK}) — bỏ qua cleanup"
    fi

    step "Background Dexopt (pm art bg-dexopt-job)"
    ui "  [INFO] Script chờ tối đa 300s (5 phút)"
    ui "  [INFO] Sau 300s, job sẽ TỰ ĐỘNG chạy ngầm — không cần reboot"
    ui "  [INFO] Hệ thống sẽ compile dựa trên thói quen dùng app (Profile-Guided)"

    _dexopt_ok=0
    if [ "$_has_pm_art" -eq 1 ] && [ "$_SDK" -ge 35 ]; then
        ui "  [INFO] Dùng pm art bg-dexopt-job (SDK 35+)..."
        _run_dexopt 300 "bg-dexopt" pm art bg-dexopt-job \
            && { ok "pm art bg-dexopt-job hoàn tất (${_rdx_total}s)"; _dexopt_ok=1; } \
            || warn "pm art bg-dexopt-job timeout/lỗi — thử fallback"
    fi

    if [ "$_dexopt_ok" -eq 0 ]; then
        if command -v cmd >/dev/null 2>&1 && [ "$_SDK" -ge 31 ]; then
            ui "  [INFO] Fallback: cmd package bg-dexopt-job (SDK 31+)..."
            _run_dexopt 300 "bg-dexopt-fallback" cmd package bg-dexopt-job \
                && { ok "cmd package bg-dexopt-job hoàn tất (${_rdx_total}s)"; _dexopt_ok=1; } \
                || warn "cmd package bg-dexopt-job thất bại/timeout"
        fi
    fi

    [ "$_dexopt_ok" -eq 0 ] && err "Tất cả dexopt paths thất bại"
    ui "  [INFO] Dexopt job đã trigger — hệ thống sẽ tiếp tục compile ngầm trong background."

    step "odrefresh (APEX Boot Image — Android 14+)"
    if [ "$_SDK" -ge 34 ]; then
        if [ -x /apex/com.android.art/bin/odrefresh ]; then
            _run_to 120 /apex/com.android.art/bin/odrefresh --check >/dev/null 2>&1
            _odr_exit=$?
            if [ "$_odr_exit" -eq 0 ]; then
                ok "odrefresh: boot image OK"
            elif [ "$_odr_exit" -eq 2 ] || [ "$_odr_exit" -eq 3 ]; then
                ui "  [INFO] odrefresh phát hiện stale boot image — compile..."
                _run_dexopt 180 "odrefresh" /apex/com.android.art/bin/odrefresh --compile \
                    && ok "odrefresh --compile hoàn tất (${_rdx_total}s)" \
                    || warn "odrefresh --compile thất bại/timeout (180s)"
            else
                warn "odrefresh exit code: $_odr_exit"
            fi
        else
            skip "odrefresh binary không tìm thấy"
        fi
    else
        skip "SDK $_SDK < 34 — odrefresh chỉ áp dụng Android 14+"
    fi

    if [ "$_thermal_bypassed" -eq 1 ]; then
        cmd thermalservice override-status 3 >/dev/null 2>&1 \
            && ok "Thermal DPM restored: override-status 3 (NORMAL)" \
            || warn "Thermal restore thất bại — service.sh sẽ thử khôi phục ở boot sau"
        rm -f "$_THERM_DPM_FLAG" 2>/dev/null
        _thermal_bypassed=0
    fi

    line; ok "Hoàn tất Rebuild ART/Dalvik"
    rotate_log
}

# ════════════════════════════════════════════════════════════════════
#  MODULE 5 — BÁO CÁO TỔNG KẾT
# ════════════════════════════════════════════════════════════════════
mod_report() {
    line; ui "  [5/5] Báo Cáo Tổng Kết"

    T_END=$(date +%s)
    _elapsed=$(( T_END - T_START ))
    _elapsed_m=$(( _elapsed / 60 ))
    _elapsed_s=$(( _elapsed % 60 ))
    _ram_after=$(get_ram_kb)
    _ram_delta=$(( _ram_after - RAM_BEFORE ))
    [ "$_ram_delta" -lt 0 ] && _ram_delta=0

    line
    ui "  ╔══════════════════════════════════════════╗"
    ui "  ║      CLEANUP ALL IN ONE ACE 5 V10.5      ║"
    ui "  ║         KẾT QUẢ TỔNG KẾT                 ║"
    ui "  ╠══════════════════════════════════════════╣"
    ui "  ║  Thời gian chạy : ${_elapsed_m}m ${_elapsed_s}s"
    ui "  ║  Dung lượng giải phóng : $(kb_to_mb_sh "$TOTAL_FREED")"
    ui "  ║  RAM trước   : $(kb_to_mb_sh "$RAM_BEFORE")"
    ui "  ║  RAM sau     : $(kb_to_mb_sh "$_ram_after")"
    ui "  ║  RAM delta   : +$(kb_to_mb_sh "$_ram_delta")"
    ui "  ╠══════════════════════════════════════════╣"
    ui "  ║  OK    : $SUCCESS_COUNT"
    ui "  ║  WARN  : $WARN_COUNT"
    ui "  ║  ERR   : $ERROR_COUNT"
    ui "  ║  SKIP  : $SKIP_COUNT"
    ui "  ╠══════════════════════════════════════════╣"
    ui "  ║  Log   : $LOG"
    ui "  ╚══════════════════════════════════════════╝"
    line

    [ "$ERROR_COUNT" -gt 5 ] && warn "Nhiều lỗi (${ERROR_COUNT}) — xem log: $LOG"
}

# ════════════════════════════════════════════════════════════════════
#  SINGLETON LOCK
# ════════════════════════════════════════════════════════════════════
_acquire_lock() {
    if ! mkdir "$CFG_LOCK_DIR" 2>/dev/null; then
        _lk_pid=""; _lk_st=""
        if [ -f "$CFG_LOCK_FILE" ]; then
            read -r _lk_pid _lk_st < "$CFG_LOCK_FILE" 2>/dev/null || true
        fi
        _lk_pid=$(safe_int "${_lk_pid:-0}")
        if [ "$_lk_pid" -gt 0 ] 2>/dev/null && [ -d "/proc/$_lk_pid" ]; then
            _cur_st="$(awk '{print $22}' /proc/$_lk_pid/stat 2>/dev/null)"
            _cur_st=$(safe_int "${_cur_st:-0}")
            if [ "$_cur_st" -eq "$(safe_int "${_lk_st:-0}")" ] && \
               [ "$_cur_st" -gt 0 ]; then
                printf "[ERR] Script đang chạy (PID %s). Thoát.\n" "$_lk_pid"
                exit 1
            fi
        fi
        rm -rf "$CFG_LOCK_DIR" "$CFG_LOCK_FILE" 2>/dev/null
        mkdir "$CFG_LOCK_DIR" 2>/dev/null || { printf "[ERR] Lock thất bại.\n"; exit 1; }
    fi
    _my_st="$(awk '{print $22}' /proc/$$/stat 2>/dev/null)"
    _my_st=$(safe_int "${_my_st:-0}")
    printf '%s %s\n' "$$" "$_my_st" > "$CFG_LOCK_FILE" 2>/dev/null
}

# ════════════════════════════════════════════════════════════════════
#  MAIN MENU
# ════════════════════════════════════════════════════════════════════
main_menu() {
    while true; do
        [ -t 1 ] && printf '\033[2J\033[H'
        ui "  ╔══════════════════════════════════════════╗"
        ui "  ║   CLEANUP ALL IN ONE ACE 5 — V10.5       ║"
        ui "  ║   @keobamien | SM8650 | ColorOS 15-16  ║"
        ui "  ║   Android 15-16 | SDK ${_SDK}            ║"
        ui "  ╚══════════════════════════════════════════╝"
        ui ""
        ui "  RAM hiện tại: $(kb_to_mb_sh "$(get_ram_kb)")"
        line
        ui "  1) Module 1 — Dọn rác ColorOS 15-16 & App Cache"
        ui "  2) Module 2 — Tối ưu KSU/Magisk/APatch & LSPosed"
        ui "  3) Module 3 — Smart Boost (Drop Cache + Logcat + FSTRIM)"
        ui "  4) Module 4 — Rebuild ART/Dalvik (APEX Safe)"
        ui "  5) Chạy tất cả (1+2+3+4)"
        ui "  6) Reboot thiết bị (20s countdown)"
        ui "  7) Reset mạng (WiFi / Data / DNS)"
        ui "  0) Thoát"
        line
        printf "  Chọn (0-7, 120s timeout): "

        _read_timed 120 "_T_"; _choice="$_RT_RESULT"

        case "$_choice" in
            "_T_")
                warn "Timeout 120s — thoát"
                return 0
                ;;
            "")
                ;; # MT Manager CR inject — re-prompt
            0) return 0 ;;
            1)
                mod_clean; mod_report
                printf "\n  Nhấn Enter để tiếp tục..."
                _read_timed 60 "" >/dev/null
                ;;
            2)
                mod_modules; mod_report
                _countdown_reboot
                printf "\n  Nhấn Enter để tiếp tục..."
                _read_timed 60 "" >/dev/null
                ;;
            3)
                mod_boost; mod_report
                printf "\n  Nhấn Enter để tiếp tục..."
                _read_timed 60 "" >/dev/null
                ;;
            4)
                mod_dalvik; mod_report
                _countdown_reboot
                printf "\n  Nhấn Enter để tiếp tục..."
                _read_timed 60 "" >/dev/null
                ;;
            5)
                mod_clean
                mod_modules
                mod_boost
                mod_dalvik
                mod_report
                _countdown_reboot
                printf "\n  Nhấn Enter để tiếp tục..."
                _read_timed 60 "" >/dev/null
                ;;
            6)
                _countdown_reboot
                printf "\n  Reboot đã huỷ hoặc bị chặn.\n"
                _read_timed 60 "" >/dev/null
                ;;
            7)
                mod_network_reset; mod_report
                printf "\n  Nhấn Enter để tiếp tục..."
                _read_timed 60 "" >/dev/null
                ;;
            *)
                warn "Lựa chọn không hợp lệ: '${_choice}'"
                sleep 1
                ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════════════
#  MAIN ENTRY POINT
# ════════════════════════════════════════════════════════════════════
main() {
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        printf "[FATAL] Script yêu cầu root. Chạy: su -c 'sh %s'\n" "$0"
        exit 1
    fi

    if [ "${AUTO_MODE:-0}" -eq 0 ]; then
        _tty_ok=0
        { [ -t 0 ] || [ -t 1 ]; } && _tty_ok=1
        # MT Manager: không có PTY — probe /dev/tty, redirect nếu mở được.
        if [ "$_tty_ok" -eq 0 ] && [ -c /dev/tty ]; then
            if ( exec </dev/tty >/dev/tty ) 2>/dev/null; then
                exec </dev/tty >/dev/tty 2>&1
                _tty_ok=1
                printf "  [INFO] TTY redirect: /dev/tty (MT Manager mode)\n"
            fi
        fi
        if [ "$_tty_ok" -eq 0 ]; then
            printf "[FATAL] Không phát hiện TTY.\n"
            printf "[FATAL]  MT Manager : chọn 'Chạy với quyền root' trực tiếp script.\n"
            printf "[FATAL]  Terminal   : su -c 'sh %s'\n" "$0"
            printf "[FATAL]  ADB        : adb shell su -c 'sh %s --auto'\n" "$0"
            exit 1
        fi
        unset _tty_ok
    else
        _log "[WARN] AUTO_MODE: TTY check bypassed"
    fi

    # AIO V2.5 fix: AUTO_MODE boot guard must run before lock acquisition.
    # Applies only to --auto/--reboot; WebUI --module keeps fast dispatch.
    if [ "${AUTO_MODE:-0}" -eq 1 ] && [ -z "${MODULE_ID:-}" ]; then
        _wait_for_boot || _log "[WARN] _wait_for_boot: timeout 60s, boot_completed chưa set — tiếp tục với rủi ro (AM/PM có thể chưa init)"
    fi

    _acquire_lock
    RAM_BEFORE=$(get_ram_kb)

    _log "════════ SESSION START V10.5 — $(date) — PID $$ — SDK ${_SDK} ════════"
    _log "Device: $(getprop ro.product.model 2>/dev/null) | $(getprop ro.build.display.id 2>/dev/null)"
    _log "RAM_BEFORE: $(kb_to_mb_sh "$RAM_BEFORE")"
    _log "AUTO_MODE: ${AUTO_MODE} | MODULE_ID: ${MODULE_ID:-<none>}"
    aio_log cleanup INFO START module=${MODULE_ID:-menu} auto=${AUTO_MODE:-0} fast=${CLEAN_FAST_MODE:-0}

    # ── WEBUI DISPATCH PATH (--module <id>) ─────────────────────────────
    # Ưu tiên cao nhất: jump thẳng đến hàm, không menu, không _wait_for_boot.
    # _read_timed trả về default ngay (AUTO_MODE=1) — không block trên WebUI.
    # Mỗi nhánh chạy mod_report để UI nhận được counters và RAM stats.
    if [ -n "${MODULE_ID:-}" ]; then
        _log "[MODULE] Dispatch: --module ${MODULE_ID}"
        case "$MODULE_ID" in
            clean)
                CLEAN_FAST_MODE=1
                CLEAN_MEASURE_SIZE=0
                mod_clean
                mod_report
                ;;
            modules)
                mod_modules
                mod_report
                ;;
            boost)
                mod_boost
                mod_report
                ;;
            dalvik)
                mod_dalvik
                mod_report
                ;;
            network)
                mod_network_reset
                mod_report
                ;;
            all)
                mod_clean
                mod_modules
                mod_boost
                mod_dalvik
                mod_network_reset
                mod_report
                ;;
            *)
                printf "[ERR] Module ID không hợp lệ: '%s'\n" "$MODULE_ID"
                printf "[ERR] Hợp lệ: clean | modules | boost | dalvik | network | all\n"
                exit 1
                ;;
        esac

    # ── AUTO MODE PATH (--auto / --reboot) ───────────────────────────────
    elif [ "${AUTO_MODE:-0}" -eq 1 ]; then
        # AIO V2.5: _wait_for_boot already ran before _acquire_lock.
        ui ""
        ui "  ╔══════════════════════════════════════════╗"
        ui "  ║   CLEANUP ALL IN ONE ACE 5 — V10.5       ║"
        ui "  ║   @keobamien | SM8650 | ColorOS 15-16  ║"
        ui "  ║   Android 15-16 | SDK ${_SDK}            ║"
        ui "  ╚══════════════════════════════════════════╝"
        ui ""
        ui "  [AUTO] Non-interactive mode — chạy mod 1+2+3+4"
        mod_clean
        mod_modules
        mod_boost
        mod_dalvik
        mod_report

        if [ "${_REBOOT_FLAG:-0}" -eq 1 ]; then
            _countdown_reboot
        fi

    # ── INTERACTIVE MENU PATH (default) ─────────────────────────────────
    else
        main_menu
    fi

    _log "════════ SESSION END — $(date) — Freed: $(kb_to_mb_sh "$TOTAL_FREED") ════════"
    if [ "${ERROR_COUNT:-0}" -gt 0 ]; then
        aio_log cleanup ERR failed module=${MODULE_ID:-menu} status=error errors=${ERROR_COUNT:-0} warnings=${WARN_COUNT:-0} skipped=${SKIP_COUNT:-0} fast=${CLEAN_FAST_MODE:-0}
    else
        aio_log cleanup SUMMARY done module=${MODULE_ID:-menu} status=ok errors=${ERROR_COUNT:-0} warnings=${WARN_COUNT:-0} skipped=${SKIP_COUNT:-0} fast=${CLEAN_FAST_MODE:-0}
    fi
    printf "\n  Log đầy đủ: %s\n" "$LOG"
}

main "$@"
