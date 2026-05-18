#!/system/bin/sh
# KSU WebUI Bridge - AIO Ace5 v3.1

_SELF="$(readlink -f "$0" 2>/dev/null)"; [ -z "$_SELF" ] && _SELF="$0"
_WEBUI_DIR="${_SELF%/*}"
_MODULE_ROOT="${_WEBUI_DIR%/*}"
_MAIN_SCRIPT="${_MODULE_ROOT}/bin/cleanup_ace5_v10_5.sh"
_BATT_SCRIPT="${_MODULE_ROOT}/bin/battery_aio_report_v1.sh"
_DBTL_SCRIPT="${_MODULE_ROOT}/bin/debloat.sh"
_PERF_SCRIPT="${_MODULE_ROOT}/bin/aio_performance.sh"
_SPOOF_SCRIPT="${_MODULE_ROOT}/bin/aio_game_spoof.sh"
_SYS_SCRIPT="${_MODULE_ROOT}/bin/aio_system_toggles.sh"
_TMP_BASE="/data/local/tmp/ca5"
_SPOOF_STATE_DIR="/data/adb/aio_ace5/state"
_SPOOF_STATE_FLAG="${_SPOOF_STATE_DIR}/game_spoof_enabled.flag"
_SPOOF_OLD_FLAG="${_MODULE_ROOT}/bin/game_spoof_enabled.flag"

_check_main() {
    [ -f "$_MAIN_SCRIPT" ] || { printf "[ERR] Script khong tim thay: %s\n" "$_MAIN_SCRIPT"; return 1; }
    [ -r "$_MAIN_SCRIPT" ] || { printf "[ERR] Khong doc duoc: %s\n" "$_MAIN_SCRIPT"; return 1; }
    return 0
}
_check_battery() {
    [ -f "$_BATT_SCRIPT" ] || { printf "[ERR] Battery wrapper khong tim thay: %s\n" "$_BATT_SCRIPT"; return 1; }
    [ -r "$_BATT_SCRIPT" ] || { printf "[ERR] Khong doc duoc: %s\n" "$_BATT_SCRIPT"; return 1; }
    return 0
}
_check_debloat() {
    [ -f "$_DBTL_SCRIPT" ] || { printf "[ERR] Debloat script khong tim thay: %s\n" "$_DBTL_SCRIPT"; return 1; }
    [ -r "$_DBTL_SCRIPT" ] || { printf "[ERR] Khong doc duoc: %s\n" "$_DBTL_SCRIPT"; return 1; }
    return 0
}
_check_perf() {
    [ -f "$_PERF_SCRIPT" ] || { printf "[ERR] Hieu nang script khong tim thay: %s\n" "$_PERF_SCRIPT"; return 1; }
    [ -r "$_PERF_SCRIPT" ] || { printf "[ERR] Khong doc duoc: %s\n" "$_PERF_SCRIPT"; return 1; }
    return 0
}
_check_spoof() {
    [ -f "$_SPOOF_SCRIPT" ] || { printf "[ERR] Game Spoof script khong tim thay: %s\n" "$_SPOOF_SCRIPT"; return 1; }
    [ -r "$_SPOOF_SCRIPT" ] || { printf "[ERR] Khong doc duoc: %s\n" "$_SPOOF_SCRIPT"; return 1; }
    return 0
}
_check_sys() {
    [ -f "$_SYS_SCRIPT" ] || { printf "[ERR] System toggles script khong tim thay: %s\n" "$_SYS_SCRIPT"; return 1; }
    [ -r "$_SYS_SCRIPT" ] || { printf "[ERR] Khong doc duoc: %s\n" "$_SYS_SCRIPT"; return 1; }
    return 0
}
_live_path() { printf '%s' "${_TMP_BASE}_live_${1}.log"; }
_done_path() { printf '%s' "${_TMP_BASE}_done_${1}.flag"; }
_pid_path()  { printf '%s' "${_TMP_BASE}_pid_${1}"; }
_mod_path()  { printf '%s' "${_TMP_BASE}_mod_${1}"; }
_valid_sid() { case "${1:-}" in ''|*[!0-9_]*|*_*_*) return 1 ;; *_*) return 0 ;; *) return 1 ;; esac; }
_pid_belongs_to_session() {
    _pid="$1"; _sid="$2"; _mod="$3"
    case "$_pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$_pid" 2>/dev/null || return 1
    _cmd="$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)"
    case "$_cmd" in *sh*|*run.sh*|*"$_mod"*|*"$_sid"*) return 0 ;; esac
    return 1
}
_flag_state() { [ -f "$1" ] && printf 'on' || printf 'off'; }
_spoof_state() {
    if [ -f "$_SPOOF_OLD_FLAG" ] && [ ! -f "$_SPOOF_STATE_FLAG" ]; then
        mkdir -p "$_SPOOF_STATE_DIR" 2>/dev/null
        : > "$_SPOOF_STATE_FLAG" 2>/dev/null && chmod 0600 "$_SPOOF_STATE_FLAG" 2>/dev/null
    fi
    _flag_state "$_SPOOF_STATE_FLAG"
}
_pid_state() {
    _pidfile="$1"
    _pid=""
    [ -f "$_pidfile" ] && _pid="$(cat "$_pidfile" 2>/dev/null | tr -d ' \t\r\n')"
    case "$_pid" in ''|*[!0-9]*) printf 'stopped'; return ;; esac
    kill -0 "$_pid" 2>/dev/null && printf 'running' || printf 'stopped'
}
_settings_state() {
    _key="$1"
    _v="$(settings get global "$_key" 2>/dev/null | tr -d ' \t\r\n')"
    [ "$_v" = "1" ] && printf 'on' || printf 'off'
}

case "${1:-}" in
  --quick-status)
    printf 'INFO_COOLDOWN=%s\n' "$(_flag_state "$_MODULE_ROOT/bin/cooldown_enabled.flag")"
    printf 'INFO_TOUCH360=%s\n' "$(_flag_state "$_MODULE_ROOT/bin/touch_360_enabled.flag")"
    printf 'INFO_TOUCH360_WORKER=%s\n' "$(_pid_state "$_MODULE_ROOT/bin/touch_360_worker.pid")"
    printf 'INFO_GAME_MAX=%s\n' "$(_flag_state "$_MODULE_ROOT/bin/game_max_enabled.flag")"
    printf 'INFO_GAME_SPOOF=%s\n' "$(_spoof_state)"
    printf 'INFO_CHARGE_MAX=%s\n' "$(_flag_state "$_MODULE_ROOT/bin/charge_max_enabled.flag")"
    [ -f "$_MODULE_ROOT/bin/thermal_shutdown_disable.flag" ] && printf 'INFO_SHUTDOWN_PROTECT=disabled\n' || printf 'INFO_SHUTDOWN_PROTECT=enabled\n'
    printf 'INFO_DEV_OPTIONS=%s\n' "$(_settings_state development_settings_enabled)"
    printf 'INFO_USB_DEBUG=%s\n' "$(_settings_state adb_enabled)"
    ;;

  --info)
    printf "MODULE_ROOT=%s\n" "$_MODULE_ROOT"
    printf "SCRIPT=%s\n" "$_MAIN_SCRIPT"
    printf "BRIDGE=%s\n" "$_SELF"
    printf "VERSION=v3.1.7\n"
    [ -f "$_MAIN_SCRIPT" ] && printf "SCRIPT_OK=1\n" || printf "SCRIPT_OK=0\n"
    [ -f "$_BATT_SCRIPT" ] && printf "BATTERY_OK=1\n" || printf "BATTERY_OK=0\n"
    [ -f "$_DBTL_SCRIPT" ] && printf "DBTL_OK=1\n" || printf "DBTL_OK=0\n"
    if [ -f "$_DBTL_SCRIPT" ]; then
        /system/bin/sh "$_DBTL_SCRIPT" --info 2>/dev/null | sed 's/^/DBTL_/'
    fi
    if [ -f "$_PERF_SCRIPT" ]; then
        /system/bin/sh "$_PERF_SCRIPT" --status 2>/dev/null | sed 's/^/PERF_/'
    fi
    if [ -f "$_SPOOF_SCRIPT" ]; then
        /system/bin/sh "$_SPOOF_SCRIPT" --status 2>/dev/null | sed 's/^/SPOOF_/'
    fi
    if [ -f "$_SYS_SCRIPT" ]; then
        /system/bin/sh "$_SYS_SCRIPT" --info 2>/dev/null | sed 's/^/SYS_/'
    fi
    ;;

  --status)
    _check_perf || exit 1
    /system/bin/sh "$_PERF_SCRIPT" --status
    [ -f "$_SPOOF_SCRIPT" ] && /system/bin/sh "$_SPOOF_SCRIPT" --status
    [ -f "$_SYS_SCRIPT" ] && /system/bin/sh "$_SYS_SCRIPT" --info
    ;;

  --start)
    _mod="${2:-}"
    if [ -z "$_mod" ]; then
        printf "[ERR] --start: thieu module ID\n"
        printf "[ERR] Hop le: clean|modules|boost|dalvik|network|all|battery-run|battery-show-latest|battery-list|debloat-info|debloat-count|debloat-apply-recommended|debloat-apply-deep|debloat-restore-all|debloat-cooldown-enable|debloat-cooldown-disable|debloat-touch360-enable|debloat-touch360-disable|performance-game-enable|performance-game-disable|performance-charge-enable|performance-charge-disable|performance-shutdown-arm|performance-shutdown-confirm|performance-shutdown-enable|performance-shutdown-disable|performance-spoof-enable|performance-spoof-disable|performance-status|system-devopts-enable|system-devopts-disable|system-usbdebug-enable|system-usbdebug-disable|system-status|reboot-device\n"
        exit 1
    fi
    case "$_mod" in
        clean|modules|boost|dalvik|network|all) _check_main || exit 1 ;;
        battery-run|battery-show-latest|battery-list) _check_battery || exit 1 ;;
        debloat-info|debloat-count|debloat-apply-recommended|debloat-apply-deep|debloat-restore-all|debloat-cooldown-enable|debloat-cooldown-disable|debloat-touch360-enable|debloat-touch360-disable) _check_debloat || exit 1 ;;
        performance-game-enable|performance-game-disable|performance-charge-enable|performance-charge-disable|performance-shutdown-arm|performance-shutdown-confirm|performance-shutdown-enable|performance-shutdown-disable|performance-status) _check_perf || exit 1 ;;
        performance-spoof-enable|performance-spoof-disable) _check_spoof || exit 1 ;;
        system-devopts-enable|system-devopts-disable|system-usbdebug-enable|system-usbdebug-disable|system-status) _check_sys || exit 1 ;;
        reboot-device) : ;;
        *) printf "[ERR] Module khong hop le: %s\n" "$_mod"; exit 1 ;;
    esac

    _SID="$(date +%s)_$$"
    _LIVE="$(_live_path "$_SID")"
    _DONE="$(_done_path "$_SID")"
    _PID_F="$(_pid_path "$_SID")"
    _MOD_F="$(_mod_path "$_SID")"

    for _old in "${_TMP_BASE}_live_"*.log "${_TMP_BASE}_done_"*.flag "${_TMP_BASE}_pid_"* "${_TMP_BASE}_mod_"*; do
        [ -f "$_old" ] || continue
        _mt=$(stat -c %Y "$_old" 2>/dev/null || printf '0')
        [ $(( $(date +%s) - _mt )) -gt 1800 ] && rm -f "$_old" 2>/dev/null
    done

    : > "$_LIVE"
    (
        case "$_mod" in
            debloat-info) /system/bin/sh "$_DBTL_SCRIPT" --info ;;
            debloat-count) /system/bin/sh "$_DBTL_SCRIPT" --count ;;
            debloat-apply-recommended) /system/bin/sh "$_DBTL_SCRIPT" --apply-recommended ;;
            debloat-apply-deep) /system/bin/sh "$_DBTL_SCRIPT" --apply-deep ;;
            debloat-restore-all) /system/bin/sh "$_DBTL_SCRIPT" --restore-all ;;
            debloat-cooldown-enable) /system/bin/sh "$_DBTL_SCRIPT" --cooldown-enable ;;
            debloat-cooldown-disable) /system/bin/sh "$_DBTL_SCRIPT" --cooldown-disable ;;
            debloat-touch360-enable) /system/bin/sh "$_DBTL_SCRIPT" --touch360-enable ;;
            debloat-touch360-disable) /system/bin/sh "$_DBTL_SCRIPT" --touch360-disable ;;
            performance-game-enable) /system/bin/sh "$_PERF_SCRIPT" --game-enable ;;
            performance-game-disable) /system/bin/sh "$_PERF_SCRIPT" --game-disable ;;
            performance-charge-enable) /system/bin/sh "$_PERF_SCRIPT" --charge-enable ;;
            performance-charge-disable) /system/bin/sh "$_PERF_SCRIPT" --charge-disable ;;
            performance-shutdown-arm) /system/bin/sh "$_PERF_SCRIPT" --shutdown-arm ;;
            performance-shutdown-confirm) /system/bin/sh "$_PERF_SCRIPT" --shutdown-confirm ;;
            performance-shutdown-enable) /system/bin/sh "$_PERF_SCRIPT" --shutdown-enable ;;
            performance-shutdown-disable) /system/bin/sh "$_PERF_SCRIPT" --shutdown-disable ;;
            performance-spoof-enable) /system/bin/sh "$_SPOOF_SCRIPT" --enable ;;
            performance-spoof-disable) /system/bin/sh "$_SPOOF_SCRIPT" --disable ;;
            performance-status) /system/bin/sh "$_PERF_SCRIPT" --status; [ -f "$_SPOOF_SCRIPT" ] && /system/bin/sh "$_SPOOF_SCRIPT" --status ;;
            system-devopts-enable) /system/bin/sh "$_SYS_SCRIPT" --devopts-enable ;;
            system-devopts-disable) /system/bin/sh "$_SYS_SCRIPT" --devopts-disable ;;
            system-usbdebug-enable) /system/bin/sh "$_SYS_SCRIPT" --usbdebug-enable ;;
            system-usbdebug-disable) /system/bin/sh "$_SYS_SCRIPT" --usbdebug-disable ;;
            system-status) /system/bin/sh "$_SYS_SCRIPT" --info ;;
            reboot-device) printf "[OK] Đang khởi động lại máy...\n"; sleep 1; /system/bin/reboot ;;
            battery-run) /system/bin/sh "$_BATT_SCRIPT" --run ;;
            battery-show-latest) /system/bin/sh "$_BATT_SCRIPT" --show-latest ;;
            battery-list) /system/bin/sh "$_BATT_SCRIPT" --list ;;
            clean|modules|boost|dalvik|network|all) /system/bin/sh "$_MAIN_SCRIPT" --module "$_mod" ;;
            *) printf "[ERR] unreachable route: %s\n" "$_mod"; exit 99 ;;
        esac >> "$_LIVE" 2>&1
        printf "EXIT:%d" "$?" > "$_DONE"
        rm -f "$_PID_F" 2>/dev/null
    ) &
    _bg_pid="$!"
    printf '%s' "$_bg_pid" > "$_PID_F"
    printf '%s' "$_mod" > "$_MOD_F"
    printf "OK:%s:%d\n" "$_SID" "$_bg_pid"
    ;;

  --poll)
    _SID="${2:-}"
    _n="${3:-1}"
    if ! _valid_sid "$_SID"; then
        printf "[ERR] --poll: thieu session ID\n"
        printf "\n===LINES:0===\n===STATUS:EXIT:1===\n"
        exit 1
    fi
    case "$_n" in ''|*[!0-9]*) _n=1 ;; esac
    _LIVE="$(_live_path "$_SID")"
    _DONE="$(_done_path "$_SID")"
    [ -f "$_LIVE" ] && tail -n "+${_n}" "$_LIVE" 2>/dev/null
    _lc=0
    [ -f "$_LIVE" ] && _lc=$(wc -l < "$_LIVE" 2>/dev/null | tr -d ' \t\n')
    printf "\n===LINES:%s===\n" "${_lc:-0}"
    if [ -f "$_DONE" ]; then
        _ei="$(cat "$_DONE" 2>/dev/null)"
        printf "===STATUS:%s===\n" "${_ei:-EXIT:0}"
        rm -f "$_DONE" "$(_pid_path "$_SID")" "$(_mod_path "$_SID")" 2>/dev/null
    else
        printf "===STATUS:RUNNING===\n"
    fi
    ;;

  --stop)
    _SID="${2:-}"
    _valid_sid "$_SID" || { printf "[ERR] --stop: session ID khong hop le\n"; exit 1; }
    _DONE="$(_done_path "$_SID")"
    _PID_F="$(_pid_path "$_SID")"
    _MOD_F="$(_mod_path "$_SID")"
    if [ -f "$_DONE" ]; then printf "ALREADY_DONE\n"; exit 0; fi
    _sp=""
    _mod=""
    [ -f "$_PID_F" ] && _sp="$(cat "$_PID_F" 2>/dev/null | tr -d ' \t\n')"
    [ -f "$_MOD_F" ] && _mod="$(cat "$_MOD_F" 2>/dev/null | tr -d '\r\n')"
    if _pid_belongs_to_session "$_sp" "$_SID" "$_mod"; then
        kill -TERM "$_sp" 2>/dev/null
        _k=0
        while [ "$_k" -lt 3 ]; do kill -0 "$_sp" 2>/dev/null || break; sleep 1; _k=$((_k+1)); done
        if kill -0 "$_sp" 2>/dev/null; then kill -9 "$_sp" 2>/dev/null; printf "KILLED:%s\n" "$_sp"
        else printf "TERMINATED:%s\n" "$_sp"; fi
    else
        printf "NO_PID\n"
    fi
    printf "EXIT:130" > "$_DONE"
    rm -f "$_PID_F" "$_MOD_F" 2>/dev/null
    ;;

  --module)
    _mod="${2:-}"
    [ -z "$_mod" ] && { printf "[ERR] --module: thieu ID\n"; exit 1; }
    _check_main || exit 1
    exec /system/bin/sh "$_MAIN_SCRIPT" --module "$_mod"
    ;;

  ""|*)
    printf "[ERR] run.sh v3.1.7: tham so khong hop le: %s\n" "${1:-<none>}"
    printf "  --info / --quick-status / --status / --start <mod> / --poll <sid> <N> / --stop <sid> / --module <mod>\n"
    printf "  mod: clean|modules|boost|dalvik|network|all|battery-run|battery-show-latest|battery-list|debloat-info|debloat-count|debloat-apply-recommended|debloat-apply-deep|debloat-restore-all|debloat-cooldown-enable|debloat-cooldown-disable|debloat-touch360-enable|debloat-touch360-disable|performance-game-enable|performance-game-disable|performance-charge-enable|performance-charge-disable|performance-shutdown-arm|performance-shutdown-confirm|performance-shutdown-enable|performance-shutdown-disable|performance-spoof-enable|performance-spoof-disable|performance-status|system-devopts-enable|system-devopts-disable|system-usbdebug-enable|system-usbdebug-disable|system-status|reboot-device\n"
    exit 1 ;;
esac
