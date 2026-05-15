#!/system/bin/sh
# Fast battery input for AIO WebUI Pin tab. No logcat or network access.

set +e

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

REPORT_DIR="${REPORT_DIR:-/sdcard/Report}"
mkdir -p "$REPORT_DIR" 2>/dev/null
TS="$(date +%Y%m%d_%H%M%S 2>/dev/null)"
[ -n "$TS" ] || TS="$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}')"
FINAL_OUT="${REPORT_DIR}/battery_input_idle_redacted_${TS}.txt"
OUT="${FINAL_OUT}.tmp.$$"
TMP="${TMPDIR:-/data/local/tmp}/aio_batt_quick_${TS}_$$"
mkdir -p "$TMP" 2>/dev/null || TMP="/tmp/aio_batt_quick_${TS}_$$"
mkdir -p "$TMP" 2>/dev/null

progress() { printf "[PROGRESS] %s|%s\n" "$1" "$2"; }
warn() { printf "[WARN] %s\n" "$1"; }
ok() { printf "[OK] %s\n" "$1"; }

run_section() {
    _title="$1"
    _pct="$2"
    _msg="$3"
    shift 3
    progress "$_pct" "$_msg"
    {
        echo
        echo "===== ${_title} ====="
        "$@"
    } >> "$OUT" 2>&1
}

run_section_bg() {
    _title="$1"
    _pct="$2"
    _msg="$3"
    shift 3
    progress "$_pct" "$_msg"
    _step="$TMP/step.out"
    (
        echo
        echo "===== ${_title} ====="
        "$@"
    ) > "$_step" 2>&1 &
    _pid="$!"
    _sec=0
    while kill -0 "$_pid" 2>/dev/null; do
        sleep 2
        _sec=$((_sec + 2))
        progress "$_pct" "${_msg}... ${_sec}s"
    done
    wait "$_pid"
    _rc="$?"
    cat "$_step" >> "$OUT" 2>/dev/null
    rm -f "$_step" 2>/dev/null
    return "$_rc"
}

run_limited_section_bg() {
    _title="$1"
    _pct="$2"
    _msg="$3"
    _timeout="$4"
    _max_lines="$5"
    shift 5
    progress "$_pct" "$_msg"
    _step="$TMP/step.out"
    _tout=""
    if [ -x /system/bin/timeout ]; then
        _tout="/system/bin/timeout"
    elif command -v timeout >/dev/null 2>&1; then
        _tout="$(command -v timeout)"
    fi
    (
        echo
        echo "===== ${_title} ====="
        if [ -n "$_tout" ]; then
            "$_tout" "$_timeout" "$@" 2>&1 | head -n "$_max_lines"
        else
            "$@" 2>&1 | head -n "$_max_lines"
        fi
    ) > "$_step" 2>&1 &
    _pid="$!"
    _sec=0
    while kill -0 "$_pid" 2>/dev/null; do
        sleep 2
        _sec=$((_sec + 2))
        progress "$_pct" "${_msg}... ${_sec}s"
    done
    wait "$_pid"
    _rc="$?"
    cat "$_step" >> "$OUT" 2>/dev/null
    rm -f "$_step" 2>/dev/null
    return "$_rc"
}

dump_sysfs_dir() {
    _dir="$1"
    [ -d "$_dir" ] || return 0
    echo "--- $_dir ---"
    for _f in "$_dir"/*; do
        [ -f "$_f" ] || continue
        _name="${_f##*/}"
        case "$_name" in
            battery_fcc|battery_soh|soh|battery_cycle_count|batt_cc|charge_full|charge_full_design|cycle_count|capacity|temp|temperature|status|voltage_now|current_now)
                _val="$(cat "$_f" 2>/dev/null | head -1)"
                if [ -n "$_val" ]; then
                    _base="${_dir##*/}"
                    printf "%s_%s=%s\n" "$_base" "$_name" "$_val"
                    printf "%s=%s\n" "$_name" "$_val"
                fi
                ;;
        esac
    done
}

aio_log battery INFO START script=battery_aio_quick_input mode=idle
{
    echo "AIO BATTERY QUICK INPUT v1"
    echo "Generated: $(date 2>/dev/null)"
    echo "Mode: idle"
    echo
    echo "===== TIME ====="
    date 2>/dev/null
    date +%s 2>/dev/null
    cat /proc/uptime 2>/dev/null
} > "$OUT"

run_section "BATTERY DUMPSYS" 15 "Doc trang thai pin" dumpsys battery
run_section "POWER SUPPLY SYSFS" 25 "Doc thong so pin" dump_sysfs_dir /sys/class/power_supply/battery
dump_sysfs_dir /sys/class/power_supply/bms >> "$OUT" 2>&1
dump_sysfs_dir /sys/class/oplus_chg/battery >> "$OUT" 2>&1

run_limited_section_bg "BATTERYSTATS SUMMARY CHARGED" 45 "Doc batterystats" 60 2500 dumpsys batterystats --charged
run_section "PACKAGE UID MAP" 62 "Doc UID package" cmd package list packages -U
run_limited_section_bg "JOBSCHEDULER" 70 "Doc jobscheduler" 25 500 dumpsys jobscheduler
run_limited_section_bg "ALARMS" 78 "Doc alarm" 25 500 dumpsys alarm
run_limited_section_bg "SENSOR SERVICE" 84 "Doc sensor" 20 350 dumpsys sensorservice
run_section "LOCATION" 90 "Bo qua vi rieng tu" printf "LOCATION_REDACTED=1\n"

{
    echo
    echo "===== REPORT END ====="
    date 2>/dev/null
    date +%s 2>/dev/null
    cat /proc/uptime 2>/dev/null
} >> "$OUT" 2>&1

rm -rf "$TMP" 2>/dev/null
mv -f "$OUT" "$FINAL_OUT" 2>/dev/null || {
    warn "Khong ghi duoc input pin"
    aio_log battery ERR failed script=battery_aio_quick_input status=error step=write_output
    exit 1
}
aio_log battery SUMMARY done script=battery_aio_quick_input status=ok report="$FINAL_OUT"
ok "Da luu input pin nhanh"
printf "Report: %s\n" "$FINAL_OUT"
