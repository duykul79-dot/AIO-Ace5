#!/system/bin/sh
# battery_input_collector_v1_1.sh
# Comprehensive Android/ColorOS battery-drain input collector.
# No logcat required. Designed for rooted Android / ColorOS 15-16 / KernelSU-Magisk-APatch.
#
# Usage:
#   su
#   sh /sdcard/battery_input_collector_v1_1.sh
#
# Optional:
#   sh /sdcard/battery_input_collector_v1_1.sh --reset-idle
#   # then turn screen off 45-60 minutes, then:
#   sh /sdcard/battery_input_collector_v1_1.sh --idle
#
# Output:
#   /sdcard/Report/battery_input_<timestamp>.txt
#   /sdcard/Report/battery_input_<timestamp>.txt.gz if gzip exists
#
# Privacy warning:
#   This report can include account names, package names, network/Wi-Fi info,
#   app usage, location-provider state, alarms/jobs, and module list.
#   Redact before sharing publicly.

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
export PATH="/system/bin:/system/xbin:/vendor/bin:/odm/bin:/product/bin:/apex/com.android.runtime/bin:$PATH"

SCRIPT_VERSION="1.1"
REPORT_DIR="/sdcard/Report"
MODE="collect"
TOP_SAMPLES="${TOP_SAMPLES:-5}"
TOP_DELAY="${TOP_DELAY:-2}"
THREAD_SAMPLES="${THREAD_SAMPLES:-3}"
THREAD_DELAY="${THREAD_DELAY:-2}"
CURRENT_SAMPLES="${CURRENT_SAMPLES:-12}"
CURRENT_DELAY="${CURRENT_DELAY:-2}"

case "${1:-}" in
  --reset-idle|reset-idle) MODE="reset_idle" ;;
  --idle|idle) MODE="idle" ;;
  --collect|"") MODE="collect" ;;
  --help|-h)
    cat <<'EOF'
battery_input_collector_v1_1.sh

Modes:
  default / --collect     Collect a full battery-drain input report.
  --reset-idle            Reset batterystats and write idle baseline note.
  --idle                  Collect full report after an idle test.

Recommended idle workflow:
  su
  sh /sdcard/battery_input_collector_v1_1.sh --reset-idle
  Turn screen off for 45-60 minutes.
  sh /sdcard/battery_input_collector_v1_1.sh --idle

Optional env:
  TOP_SAMPLES=5 TOP_DELAY=2 THREAD_SAMPLES=3 THREAD_DELAY=2 CURRENT_SAMPLES=12 CURRENT_DELAY=2
EOF
    exit 0
    ;;
  *)
    echo "Unknown arg: $1"
    echo "Use --help"
    exit 2
    ;;
esac

aio_log battery INFO START script=battery_input_collector mode=$MODE
if [ "$(id -u 2>/dev/null)" != "0" ]; then
  echo "[INFO] Not root. Re-executing via su..."
  exec su -c "sh '$0' '$1'"
fi

mkdir -p "$REPORT_DIR" 2>/dev/null
TS="$(date +%Y%m%d_%H%M%S 2>/dev/null)"
[ -n "$TS" ] || TS="$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}')"
OUT="${REPORT_DIR}/battery_input_FULL_PRIVATE_${MODE}_${TS}.txt"
TMPDIR="/data/local/tmp/batt_input_${TS}_$$"
mkdir -p "$TMPDIR" 2>/dev/null

have() { command -v "$1" >/dev/null 2>&1; }

run_raw() {
  # $1 title, $2 timeout seconds, $3... command
  _title="$1"; _timeout="$2"; shift 2
  echo
  echo "===== ${_title} ====="
  echo "\$ $*"
  echo "--- BEGIN ${_title} ---"
  if have timeout; then
    timeout "$_timeout" "$@" 2>&1
    _rc=$?
  else
    "$@" 2>&1
    _rc=$?
  fi
  echo "--- END ${_title} rc=${_rc} ---"
}

run_sh() {
  # $1 title, $2 timeout seconds, $3 shell code
  _title="$1"; _timeout="$2"; _code="$3"
  echo
  echo "===== ${_title} ====="
  echo "\$ ${_code}"
  echo "--- BEGIN ${_title} ---"
  if have timeout; then
    timeout "$_timeout" sh -c "$_code" 2>&1
    _rc=$?
  else
    sh -c "$_code" 2>&1
    _rc=$?
  fi
  echo "--- END ${_title} rc=${_rc} ---"
}

section_note() {
  echo
  echo "===== $1 ====="
  shift
  while [ "$#" -gt 0 ]; do
    echo "$1"
    shift
  done
}

collect_power_supply_sysfs() {
  for d in /sys/class/power_supply/*; do
    [ -d "$d" ] || continue
    echo "--- $d ---"
    for f in \
      type status health present capacity charge_counter charge_full charge_full_design \
      current_now current_avg voltage_now temp technology cycle_count charge_control_limit \
      input_current_limit constant_charge_current_max constant_charge_voltage_max \
      online usb_type manufacturer model_name serial_number
    do
      [ -r "$d/$f" ] && printf "%s=" "$f" && cat "$d/$f" 2>/dev/null
    done
  done
}

collect_current_samples() {
  i=1
  while [ "$i" -le "$CURRENT_SAMPLES" ]; do
    echo "--- sample $i / $CURRENT_SAMPLES @ $(date '+%H:%M:%S' 2>/dev/null) ---"
    for d in /sys/class/power_supply/*; do
      [ -d "$d" ] || continue
      name="${d##*/}"
      cap="$(cat "$d/capacity" 2>/dev/null)"
      cur="$(cat "$d/current_now" 2>/dev/null)"
      avg="$(cat "$d/current_avg" 2>/dev/null)"
      volt="$(cat "$d/voltage_now" 2>/dev/null)"
      temp="$(cat "$d/temp" 2>/dev/null)"
      status="$(cat "$d/status" 2>/dev/null)"
      [ -n "$cap$cur$avg$volt$temp$status" ] && echo "$name capacity=$cap current_now=$cur current_avg=$avg voltage_now=$volt temp=$temp status=$status"
    done
    sleep "$CURRENT_DELAY"
    i=$((i+1))
  done
}

collect_thermal_sysfs() {
  for z in /sys/class/thermal/thermal_zone*; do
    [ -d "$z" ] || continue
    printf "%s " "${z##*/}"
    [ -r "$z/type" ] && printf "type=%s " "$(cat "$z/type" 2>/dev/null)"
    [ -r "$z/temp" ] && printf "temp=%s " "$(cat "$z/temp" 2>/dev/null)"
    [ -r "$z/mode" ] && printf "mode=%s " "$(cat "$z/mode" 2>/dev/null)"
    echo
  done
  for c in /sys/class/thermal/cooling_device*; do
    [ -d "$c" ] || continue
    printf "%s " "${c##*/}"
    [ -r "$c/type" ] && printf "type=%s " "$(cat "$c/type" 2>/dev/null)"
    [ -r "$c/cur_state" ] && printf "cur_state=%s " "$(cat "$c/cur_state" 2>/dev/null)"
    [ -r "$c/max_state" ] && printf "max_state=%s " "$(cat "$c/max_state" 2>/dev/null)"
    echo
  done
}

collect_cpu_freq() {
  for c in /sys/devices/system/cpu/cpu[0-9]*; do
    [ -d "$c" ] || continue
    cpu="${c##*/}"
    echo "--- $cpu ---"
    for f in \
      cpufreq/scaling_cur_freq cpufreq/cpuinfo_cur_freq cpufreq/scaling_min_freq \
      cpufreq/scaling_max_freq cpufreq/scaling_governor cpufreq/cpuinfo_max_freq \
      cpufreq/cpuinfo_min_freq online
    do
      [ -r "$c/$f" ] && printf "%s=" "$f" && cat "$c/$f" 2>/dev/null
    done
  done
}

collect_devfreq() {
  for d in /sys/class/devfreq/*; do
    [ -d "$d" ] || continue
    echo "--- $d ---"
    for f in name governor cur_freq min_freq max_freq available_frequencies available_governors load; do
      [ -r "$d/$f" ] && printf "%s=" "$f" && cat "$d/$f" 2>/dev/null
    done
  done
}

collect_modules() {
  for base in /data/adb/modules /data/adb/ksu/modules /data/adb/apatch/modules /data/adb/magisk/modules; do
    [ -d "$base" ] || continue
    echo "### $base ###"
    ls -la "$base" 2>/dev/null
    for m in "$base"/*; do
      [ -d "$m" ] || continue
      echo "--- MODULE ${m##*/} ---"
      [ -f "$m/module.prop" ] && cat "$m/module.prop" 2>/dev/null
      for f in disable remove update skip_mount service.sh post-fs-data.sh uninstall.sh sepolicy.rule; do
        [ -e "$m/$f" ] && ls -l "$m/$f" 2>/dev/null
      done
    done
  done
}

collect_settings_relevant() {
  echo "--- global battery/power/location/display/network related ---"
  settings list global 2>/dev/null | grep -iE 'battery|power|idle|doze|device_idle|adaptive|sleep|wifi|mobile|network|location|bluetooth|sync|thermal|anim|refresh|hz|background|standby|low_power|adb|development' || true
  echo "--- secure battery/power/location/display related ---"
  settings list secure 2>/dev/null | grep -iE 'battery|power|idle|doze|location|sensor|motion|gesture|sleep|aod|ambient|display|refresh|wake|assistant|voice|activity|recognition|background' || true
  echo "--- system battery/power/display related ---"
  settings list system 2>/dev/null | grep -iE 'battery|power|brightness|screen|display|refresh|sleep|timeout|gesture|wake|aod|ambient|vibrate' || true
}

collect_oplus_props() {
  getprop | grep -iE 'oplus|oppo|coloros|battery|thermal|power|logd|ota|cota|sau|preload|monitor|hotstart|display|refresh|fps|doze|idle|sensor|gesture|location|wifi|modem|radio|deepthinker|athena|midas|nas|metis|scene|stats|ad|collect' 2>/dev/null
}

collect_uid_maps() {
  echo "--- /data/system/packages.list uid map fallback ---"
  if [ -r /data/system/packages.list ]; then
    # Format usually: package uid debugFlags dataDir seinfo targetSdk ...
    awk '{if ($1 ~ /^[A-Za-z0-9_.-]+$/ && $2 ~ /^[0-9]+$/) print "package:"$1" uid:"$2}' /data/system/packages.list 2>/dev/null
  else
    echo "packages.list not readable"
  fi
  echo "--- cmd package list packages -U ---"
  cmd package list packages -U 2>/dev/null
  echo "--- pm list packages -U fallback ---"
  pm list packages -U 2>/dev/null
  echo "--- third party packages ---"
  cmd package list packages -3 -U 2>/dev/null || pm list packages -3 -U 2>/dev/null
  echo "--- system packages ---"
  cmd package list packages -s -U 2>/dev/null || pm list packages -s -U 2>/dev/null
  echo "--- disabled packages ---"
  cmd package list packages -d -U 2>/dev/null || pm list packages -d -U 2>/dev/null
  echo "--- enabled packages ---"
  cmd package list packages -e -U 2>/dev/null || pm list packages -e -U 2>/dev/null
}

collect_appops() {
  for op in \
    RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND WAKE_LOCK \
    ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION \
    ACTIVITY_RECOGNITION BODY_SENSORS CAMERA RECORD_AUDIO \
    READ_DEVICE_IDENTIFIERS SCHEDULE_EXACT_ALARM USE_EXACT_ALARM \
    START_FOREGROUND VIBRATE BLUETOOTH_SCAN BLUETOOTH_CONNECT
  do
    echo "--- appops allow: $op ---"
    cmd appops query-op "$op" allow 2>/dev/null
    echo "--- appops ignore/deny: $op ---"
    cmd appops query-op "$op" ignore 2>/dev/null
    cmd appops query-op "$op" deny 2>/dev/null
  done
}

collect_proc_uid_io() {
  echo "--- /proc/uid_time_in_state if available ---"
  cat /proc/uid_time_in_state 2>/dev/null
  echo "--- /proc/uid_io/stats if available ---"
  cat /proc/uid_io/stats 2>/dev/null
  echo "--- /proc/uid_cputime/show_uid_stat if available ---"
  cat /proc/uid_cputime/show_uid_stat 2>/dev/null
  echo "--- /proc/net/xt_qtaguid/stats if available ---"
  cat /proc/net/xt_qtaguid/stats 2>/dev/null | head -2000
}

if [ "$MODE" = "reset_idle" ]; then
  mkdir -p "$REPORT_DIR" 2>/dev/null
  BASE="${REPORT_DIR}/battery_idle_baseline_${TS}.txt"
  {
    echo "===== BATTERY IDLE BASELINE ====="
    date
    date +%s
    cat /proc/uptime
    echo
    echo "===== BEFORE RESET BATTERY ====="
    dumpsys battery 2>&1
    echo
    echo "===== RESET BATTERYSTATS ====="
    dumpsys batterystats --reset 2>&1
    echo
    echo "===== AFTER RESET BATTERY ====="
    dumpsys battery 2>&1
    echo
    echo "Instruction: turn screen off for 45-60 minutes, then run:"
    echo "  su -c sh /sdcard/battery_input_collector_v1_1.sh --idle"
  } > "$BASE"
  echo "Idle baseline saved to: $BASE"
  echo "Now turn screen off for 45-60 minutes, then run collector with --idle."
  exit 0
fi

{
echo "===== BATTERY INPUT COLLECTOR ====="
echo "version=${SCRIPT_VERSION}"
echo "mode=${MODE}"
date
date +%s
cat /proc/uptime 2>/dev/null
echo "report=$OUT"
echo "tmpdir=$TMPDIR"
echo

section_note "READ ME" \
  "This is a raw input report for later battery-drain analysis." \
  "It intentionally avoids logcat, because logd/logcat may be disabled." \
  "For idle drain, run --reset-idle, turn screen off 45-60 minutes, then run --idle." \
  "This file may contain account names, package names, Wi-Fi/network data, app usage, and root module data."

run_sh "ROOT / ENV INFO" 20 '
echo "id=$(id 2>/dev/null)"
echo "whoami=$(whoami 2>/dev/null)"
echo "shell=$SHELL"
echo "path=$PATH"
echo "selinux=$(getenforce 2>/dev/null)"
echo "uname=$(uname -a 2>/dev/null)"
echo "mount namespace pid=$$"
'

run_sh "TIME / UPTIME / BOOT" 20 '
date
date +%s
cat /proc/uptime 2>/dev/null
getprop sys.boot_completed
getprop ro.runtime.firstboot
getprop ro.boottime.init
getprop ro.boottime.init.first_stage
getprop ro.boottime.bootanim
uptime 2>/dev/null
'

run_sh "BUILD / DEVICE / ROM" 30 '
getprop ro.build.version.release
getprop ro.build.version.sdk
getprop ro.build.version.incremental
getprop ro.build.version.ota
getprop ro.build.display.id
getprop ro.product.model
getprop ro.product.device
getprop ro.product.brand
getprop ro.product.manufacturer
getprop ro.product.board
getprop ro.hardware
getprop ro.soc.model
getprop ro.boot.hardware
getprop ro.boot.slot_suffix
getprop ro.boot.verifiedbootstate
getprop ro.boot.vbmeta.device_state
getprop ro.boot.flash.locked
'

run_sh "RELEVANT GETPROP FILTER" 60 'getprop | grep -iE "oplus|oppo|coloros|battery|thermal|power|logd|ota|cota|sau|preload|monitor|hotstart|display|refresh|fps|doze|idle|sensor|gesture|location|wifi|modem|radio|deepthinker|athena|midas|nas|metis|scene|stats|ad|collect" 2>/dev/null'

echo
echo "===== PACKAGE UID MAP ====="
collect_uid_maps 2>&1

echo
echo "===== APPOPS SNAPSHOT ====="
collect_appops 2>&1

echo
echo "===== BATTERY DUMPSYS ====="
dumpsys battery 2>&1
echo
echo "===== BATTERY PROPERTIES ====="
dumpsys batteryproperties 2>&1
echo
echo "===== POWER SUPPLY SYSFS ====="
collect_power_supply_sysfs 2>&1
echo
echo "===== CURRENT / VOLTAGE LIVE SAMPLES ====="
collect_current_samples 2>&1

run_raw "THERMAL SERVICE" 60 dumpsys thermalservice
echo
echo "===== THERMAL SYSFS ====="
collect_thermal_sysfs 2>&1

run_sh "CPU TOP PROCESS SAMPLES" 90 "top -b -n ${TOP_SAMPLES} -d ${TOP_DELAY} | head -400"
run_sh "CPU TOP THREAD SAMPLES" 90 "top -H -b -n ${THREAD_SAMPLES} -d ${THREAD_DELAY} | head -400"
run_sh "CPU /PROC STAT BEFORE-AFTER" 20 '
echo "--- before ---"
cat /proc/stat 2>/dev/null | head -40
sleep 3
echo "--- after ---"
cat /proc/stat 2>/dev/null | head -40
'
echo
echo "===== CPU FREQ SYSFS ====="
collect_cpu_freq 2>&1
echo
echo "===== DEVFREQ SYSFS ====="
collect_devfreq 2>&1

run_raw "PROCESS LIST DEFAULT" 60 ps -A
run_sh "PROCESS LIST EXTENDED" 60 'ps -A -o USER,PID,PPID,VSZ,RSS,WCHAN,ADDR,S,NAME 2>/dev/null || ps -A -o USER,PID,PPID,VSZ,RSS,STAT,ARGS 2>/dev/null || true'
echo
echo "===== PROC UID CPU / IO / NETWORK RAW ====="
collect_proc_uid_io 2>&1

run_raw "MEMINFO DUMPSYS" 80 dumpsys meminfo
run_raw "LMKD" 40 dumpsys lmkd
run_raw "PROCSTATS LAST 3H" 120 dumpsys procstats --hours 3
run_raw "PROCSTATS LAST 24H" 160 dumpsys procstats --hours 24
run_raw "USAGESTATS" 120 dumpsys usagestats

run_raw "POWER / WAKELOCK" 80 dumpsys power
run_sh "KERNEL WAKEUP SOURCES" 60 '
cat /sys/kernel/debug/wakeup_sources 2>/dev/null
cat /d/wakeup_sources 2>/dev/null
cat /proc/wakelocks 2>/dev/null
'
run_sh "SUSPEND STATS" 30 '
cat /sys/power/suspend_stats 2>/dev/null
cat /sys/kernel/debug/suspend_stats 2>/dev/null
cat /d/suspend_stats 2>/dev/null
'
run_raw "BATTERYSTATS SUMMARY CHARGED" 180 dumpsys batterystats --charged
run_raw "BATTERYSTATS CHECKIN" 180 dumpsys batterystats --checkin
run_raw "BATTERYSTATS HISTORY" 180 dumpsys batterystats --history

run_raw "ACTIVITY PROCESSES" 120 dumpsys activity processes
run_raw "ACTIVITY FOREGROUND SERVICES / SERVICES" 180 dumpsys activity services
run_raw "ACTIVITY BROADCASTS" 120 dumpsys activity broadcasts
run_raw "JOBSCHEDULER" 180 dumpsys jobscheduler
run_raw "ALARMS" 180 dumpsys alarm
run_raw "DEVICE IDLE" 80 dumpsys deviceidle
run_raw "POWER EXEMPTION / TEMP ALLOWLIST" 60 dumpsys deviceidle whitelist

run_raw "LOCATION" 120 dumpsys location
run_raw "GNSS / GPS" 80 dumpsys gnss
run_raw "SENSOR SERVICE" 120 dumpsys sensorservice
run_raw "SENSOR PRIVACY" 40 dumpsys sensor_privacy

run_raw "DISPLAY" 120 dumpsys display
run_raw "WINDOW FIRST 800 LINES" 60 sh -c 'dumpsys window 2>/dev/null | head -800'
run_raw "SURFACEFLINGER BASIC" 60 sh -c 'dumpsys SurfaceFlinger --list 2>/dev/null; echo; dumpsys SurfaceFlinger --display-id 2>/dev/null; echo; dumpsys SurfaceFlinger 2>/dev/null | head -500'
run_raw "INPUT" 60 dumpsys input

run_raw "AUDIO" 120 dumpsys audio
run_raw "MEDIA AUDIO FLINGER" 80 dumpsys media.audio_flinger
run_raw "MEDIA SESSION" 80 dumpsys media_session
run_raw "VIBRATOR" 40 dumpsys vibrator

run_raw "NETWORK STATS" 180 dumpsys netstats
run_raw "CONNECTIVITY" 120 dumpsys connectivity
run_raw "WIFI FULL" 180 dumpsys wifi
run_raw "WIFI SCANNING" 80 dumpsys wifiscanner
run_raw "TELEPHONY REGISTRY" 100 dumpsys telephony.registry
run_raw "TELEPHONY SUBSCRIPTION" 80 dumpsys isub
run_raw "BLUETOOTH MANAGER" 80 dumpsys bluetooth_manager

run_raw "NOTIFICATION" 100 dumpsys notification
run_raw "APPWIDGET" 80 dumpsys appwidget
run_raw "CONTENT SYNC" 120 dumpsys content
run_raw "ACCOUNT" 80 dumpsys account

echo
echo "===== SETTINGS RELEVANT ====="
collect_settings_relevant 2>&1

echo
echo "===== ROOT MODULES ====="
collect_modules 2>&1

run_sh "MOUNTS RELEVANT" 50 'mount | grep -E " /system/bin/logd | /system/bin/logcat | /system/bin/update_engine |/data/adb|magisk|ksu|apatch|overlay|tmpfs" || mount'
run_sh "LOGD / UPDATE_ENGINE STATE" 30 '
echo "logd pid: $(pidof logd 2>/dev/null)"
echo "update_engine pid: $(pidof update_engine 2>/dev/null)"
getprop init.svc.logd
getprop init.svc.update_engine
mount | grep -E " /system/bin/logd | /system/bin/logcat | /system/bin/update_engine | /system/bin/update_engine_sideload " 2>/dev/null
ls -l /system/bin/logd /system/bin/logcat /system/bin/update_engine /system/bin/update_engine_sideload 2>/dev/null
'

run_sh "OPLUS / COLOROS SUSPECT PACKAGE QUICK STATUS" 60 '
for P in \
com.opos.ads \
com.heytap.speechassist \
com.oplus.deepthinker \
com.oplus.gesture \
com.oplus.nas \
com.oplus.metis \
com.oplus.aiunit \
com.coloros.sceneservice \
com.oplus.athena \
com.oplus.midas \
com.oplus.onetrace \
com.oplus.statistics.rom \
com.oplus.ota \
com.oplus.cota \
com.oplus.romupdate \
com.heytap.mcs \
com.heytap.accessory \
com.facebook.orca \
org.telegram.messenger \
com.google.android.gms \
com.google.android.googlequicksearchbox
do
  echo "--- $P ---"
  cmd package path "$P" 2>/dev/null || pm path "$P" 2>/dev/null
  cmd package list packages -U "$P" 2>/dev/null || pm list packages -U "$P" 2>/dev/null
  cmd appops get "$P" 2>/dev/null | head -120
done
'

echo
echo "===== REPORT END ====="
date
date +%s
cat /proc/uptime 2>/dev/null
} > "$OUT" 2>&1

# Create compressed copy if possible.
if have gzip; then
  gzip -c "$OUT" > "${OUT}.gz" 2>/dev/null && GZ="${OUT}.gz" || GZ=""
else
  GZ=""
fi

rm -rf "$TMPDIR" 2>/dev/null

aio_log battery SUMMARY done script=battery_input_collector mode=$MODE status=ok report="$OUT"
echo "Saved to: $OUT"
[ -n "$GZ" ] && echo "Compressed: $GZ"
echo "Size:"
ls -lh "$OUT" "$GZ" 2>/dev/null
