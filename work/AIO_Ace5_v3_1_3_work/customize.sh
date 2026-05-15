#!/system/bin/sh
# AIO Ace5 installer
# Compatible with Magisk / KernelSU / APatch customize.sh

SKIPUNZIP=0

if ! command -v ui_print >/dev/null 2>&1; then
    ui_print() { printf "%s\n" "$1"; }
fi

_line() { ui_print "--------------------------------"; }
_blank() { ui_print " "; }
_info() { ui_print " [INFO] $1"; }
_ok() { ui_print " [OK]   $1"; }
_warn() { ui_print " [WARN] $1"; }
_err() { ui_print " [ERR]  $1"; }

_device="$(getprop ro.product.model 2>/dev/null)"
_sdk="$(getprop ro.build.version.sdk 2>/dev/null)"
_abi="$(getprop ro.product.cpu.abi 2>/dev/null)"
_sdk="${_sdk:-0}"
_sdk_int=0
expr "$_sdk" + 0 >/dev/null 2>&1 && _sdk_int=$(expr "$_sdk" + 0) || true

_mod_name="$(grep -m1 '^name=' "$MODPATH/module.prop" 2>/dev/null | cut -d= -f2-)"
_mod_ver="$(grep -m1 '^version=' "$MODPATH/module.prop" 2>/dev/null | cut -d= -f2-)"
[ -n "$_mod_name" ] || _mod_name="AIO Ace5"
[ -n "$_mod_ver" ] || _mod_ver="unknown"

_line
ui_print " $_mod_name ($_mod_ver)"
ui_print " by @keobamien"
_line
ui_print " Thiết bị : ${_device:-unknown}"
ui_print " Android  : SDK ${_sdk:-unknown}"
ui_print " ABI      : ${_abi:-unknown}"
_blank
ui_print " Tính năng: Debloat, Dọn rác, Pin, Hiệu năng"
ui_print " Lưu ý    : Cấu hình hiệu năng cần reboot sau khi bật"
_line

if [ "$_sdk_int" -lt 31 ] 2>/dev/null; then
    _err "SDK ${_sdk} < 31 - không hỗ trợ thiết bị này."
    abort "Cài đặt thất bại: SDK không phù hợp."
fi

if [ "$_sdk_int" -lt 35 ] 2>/dev/null; then
    _warn "SDK ${_sdk} < 35 - một số tính năng có thể fallback/skip."
fi

case "${_abi:-}" in
    arm64-v8a) ;;
    *) _warn "Module tối ưu cho ARM64; ABI hiện tại: ${_abi:-unknown}." ;;
esac

if [ "${KSU:-false}" = "true" ] || [ -d /data/adb/ksu ]; then
    _ok "KernelSU: dùng WebUI trong Modules -> AIO Ace5"
elif [ -d /data/adb/magisk ]; then
    _info "Magisk: có thể chạy script thủ công bằng root shell"
else
    _info "Root framework: APatch hoặc không xác định"
fi

_blank
_info "Kiểm tra gói cài đặt..."

_missing=0
for _f in \
    "$MODPATH/bin/cleanup_ace5_v10_5.sh" \
    "$MODPATH/bin/debloat.sh" \
    "$MODPATH/bin/debloat_catalog.conf" \
    "$MODPATH/bin/touch_360_worker.sh" \
    "$MODPATH/bin/battery_input_collector_v1_1.sh" \
    "$MODPATH/bin/battery_actor_analyzer_v1_2_2.sh" \
    "$MODPATH/bin/battery_aio_report_v1.sh" \
    "$MODPATH/bin/battery_aio_quick_input_v1.sh" \
    "$MODPATH/bin/aio_performance.sh" \
    "$MODPATH/bin/aio_system_toggles.sh" \
    "$MODPATH/bin/aio_extreme_generator.sh" \
    "$MODPATH/bin/aio_game_spoof.sh" \
    "$MODPATH/bin/game_spoof_profiles.conf" \
    "$MODPATH/bin/game_spoof_targets.conf" \
    "$MODPATH/bin/game_spoof_cpu_blacklist.conf" \
    "$MODPATH/bin/game_spoof_cpuinfo.txt" \
    "$MODPATH/bin/copg_engine/controller_arm64" \
    "$MODPATH/zygisk/arm64-v8a.so" \
    "$MODPATH/webroot/run.sh" \
    "$MODPATH/webroot/index.html" \
    "$MODPATH/module.prop" \
    "$MODPATH/post-fs-data.sh" \
    "$MODPATH/service.sh" \
    "$MODPATH/uninstall.sh" \
    "$MODPATH/sepolicy.rule" \
    "$MODPATH/common/stub_daemon.sh" \
    "$MODPATH/common/stub_cmd.sh"
do
    if [ ! -f "$_f" ]; then
        _err "Thiếu: ${_f#$MODPATH/}"
        _missing=$((_missing+1))
    fi
done

if [ "$_missing" -gt 0 ]; then
    abort "Cài đặt thất bại: thiếu ${_missing} file."
fi
_ok "Gói cài đặt hợp lệ"

# Bootloop safety cleanup: remove stale generated payload and unsafe performance flags on update.
rm -rf "$MODPATH/bin/extreme_gt_payload_generated" 2>/dev/null
rm -f "$MODPATH/bin/game_max_enabled.flag" "$MODPATH/bin/charge_max_enabled.flag" "$MODPATH/bin/thermal_shutdown_disable.flag" 2>/dev/null

_blank
_info "Thiết lập quyền file..."

set_perm "$MODPATH/bin/cleanup_ace5_v10_5.sh" root root 0700
set_perm "$MODPATH/bin/debloat.sh" root root 0700
set_perm "$MODPATH/bin/debloat_catalog.conf" root root 0644
set_perm "$MODPATH/bin/touch_360_worker.sh" root root 0755
set_perm "$MODPATH/bin/aio_performance.sh" root root 0700
set_perm "$MODPATH/bin/aio_system_toggles.sh" root root 0700
set_perm "$MODPATH/bin/aio_extreme_generator.sh" root root 0700
set_perm "$MODPATH/bin/aio_game_spoof.sh" root root 0700
set_perm "$MODPATH/bin/game_spoof_profiles.conf" root root 0600
set_perm "$MODPATH/bin/game_spoof_targets.conf" root root 0600
set_perm "$MODPATH/bin/game_spoof_cpu_blacklist.conf" root root 0600
set_perm "$MODPATH/bin/game_spoof_cpuinfo.txt" root root 0600
set_perm "$MODPATH/bin/copg_engine/controller_arm64" root root 0755
[ -f "$MODPATH/bin/copg_engine/controller_armv7" ] && set_perm "$MODPATH/bin/copg_engine/controller_armv7" root root 0755
set_perm "$MODPATH/zygisk/arm64-v8a.so" root root 0644
[ -f "$MODPATH/zygisk/armeabi-v7a.so" ] && set_perm "$MODPATH/zygisk/armeabi-v7a.so" root root 0644
set_perm "$MODPATH/bin/battery_input_collector_v1_1.sh" root root 0700
set_perm "$MODPATH/bin/battery_actor_analyzer_v1_2_2.sh" root root 0700
set_perm "$MODPATH/bin/battery_aio_report_v1.sh" root root 0700
set_perm "$MODPATH/bin/battery_aio_quick_input_v1.sh" root root 0700
set_perm "$MODPATH/webroot/run.sh" root root 0700
set_perm "$MODPATH/webroot/index.html" root root 0644
set_perm "$MODPATH/post-fs-data.sh" root root 0700
set_perm "$MODPATH/service.sh" root root 0700
set_perm "$MODPATH/common/stub_daemon.sh" root root 0700
set_perm "$MODPATH/common/stub_cmd.sh" root root 0700
set_perm "$MODPATH/uninstall.sh" root root 0700
set_perm "$MODPATH/sepolicy.rule" root root 0644
set_perm "$MODPATH/bin" root root 0750
set_perm "$MODPATH/bin/copg_engine" root root 0750
set_perm "$MODPATH/zygisk" root root 0755
set_perm "$MODPATH/webroot" root root 0755
_ok "Quyền file đã thiết lập"

_blank
ui_print " Sau khi cài:"
ui_print " - Reboot thiết bị để module hoạt động đầy đủ"
ui_print " - Mở WebUI trong KernelSU để bật/tắt từng tính năng"
ui_print " - Module không tự Debloat/Dọn rác khi boot"
_line
ui_print " Hoàn tất cài đặt ${_mod_name} (${_mod_ver})"
_line
