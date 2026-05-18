#!/system/bin/sh
# AIO Ace5 v3.1 uninstall.sh
# Best-effort rollback for persistent runtime changes.

MODDIR="${0%/*}"
BACKUP_FILE="${MODDIR}/bin/debloat_backup.list"
FLAG="${MODDIR}/bin/cooldown_enabled.flag"
PERF_SCRIPT="${MODDIR}/bin/aio_performance.sh"
SPOOF_SCRIPT="${MODDIR}/bin/aio_game_spoof.sh"
SPOOF_STATE_DIR="/data/adb/aio_ace5/state"
SPOOF_STATE_FLAG="${SPOOF_STATE_DIR}/game_spoof_enabled.flag"
TOUCH360_FLAG="${MODDIR}/bin/touch_360_enabled.flag"
TOUCH360_PID="${MODDIR}/bin/touch_360_worker.pid"
PAYLOAD="${MODDIR}/bin/extreme_gt_payload_generated"
MANIFEST="${PAYLOAD}/MANIFEST"
COPG_COMPAT_DIR="/data/adb/modules/COPG"
COPG_COMPAT_MARKER="$COPG_COMPAT_DIR/.aio_owned"
COPG_COMPAT_SIGNATURE="$COPG_COMPAT_DIR/.aio_signature_v31"
COPG_COMPAT_JSON="$COPG_COMPAT_DIR/COPG.json"
COPG_COMPAT_CPUINFO="$COPG_COMPAT_DIR/cpuinfo_spoof"
COPG_COMPAT_CONTROLLER="$COPG_COMPAT_DIR/controller"
COPG_CONTROLLER_PID="/data/local/tmp/aio_game_spoof_copg_controller.pid"

_mount_has() {
  TARGET="$1"
  awk -v t="$TARGET" '$2==t{found=1} END{exit !found}' /proc/mounts 2>/dev/null || \
    mount | awk -v t="$TARGET" '$2==t{found=1} END{exit !found}' 2>/dev/null
}

is_aio_copg_shim() {
  [ -f "$COPG_COMPAT_MARKER" ] || return 1
  [ -f "$COPG_COMPAT_SIGNATURE" ] || return 1
  grep -qx 'AIO_Ace5_v3.1_COPG_SHIM' "$COPG_COMPAT_SIGNATURE" 2>/dev/null
}

remove_aio_copg_shim() {
  is_aio_copg_shim || return 0
  rm -f "$COPG_COMPAT_JSON" "$COPG_COMPAT_CPUINFO" "$COPG_COMPAT_CONTROLLER" \
    "$COPG_COMPAT_MARKER" "$COPG_COMPAT_SIGNATURE" 2>/dev/null
  rmdir "$COPG_COMPAT_DIR" 2>/dev/null
}

unmount_target() {
  TARGET="$1"
  _mount_has "$TARGET" && umount "$TARGET" 2>/dev/null
}

unmount_manifest_groups() {
  [ -f "$MANIFEST" ] || return 0
  while IFS='|' read -r GROUP TARGET; do
    case "$GROUP" in game|charge|thermal_policy|high_temp) [ -n "$TARGET" ] && unmount_target "$TARGET" ;; esac
  done < "$MANIFEST"
}

kill_pidfile() {
  PIDFILE="$1"
  [ -f "$PIDFILE" ] || return 0
  PID="$(cat "$PIDFILE" 2>/dev/null | tr -d ' \t\r\n')"
  case "$PID" in ''|*[!0-9]*) ;; *) kill "$PID" 2>/dev/null; sleep 1; kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null ;; esac
  rm -f "$PIDFILE" 2>/dev/null
}

enable_pkg() {
  PKG="$1"
  [ -n "$PKG" ] || return 0
  pm enable --user 0 "$PKG" >/dev/null 2>&1 && return 0
  pm enable "$PKG" >/dev/null 2>&1 && return 0
  pm install-existing --user 0 "$PKG" >/dev/null 2>&1 && pm enable --user 0 "$PKG" >/dev/null 2>&1
}

# Remove systemless binds if uninstall is executed before reboot.
for T in \
  /system/bin/logd \
  /system/bin/logcat \
  /system/bin/update_engine \
  /system/bin/update_engine_sideload
do
  unmount_target "$T"
done

# Re-enable all packages recorded by debloat backup.
# Backup format: pkg|action|section|timestamp -> tach field bang IFS='|'.
if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
  while IFS='|' read -r PKG _rest; do
    case "$PKG" in ""|\#*) continue ;; esac
    enable_pkg "$PKG"
  done < "$BACKUP_FILE"
fi

# Fallback list: covers Cooldown packages and AIO extra blockers.
for PKG in \
  com.oplus.statistics.rom \
  com.nearme.statistics.rom \
  com.heytap.statistics \
  com.oppo.statistics \
  com.oplus.ota \
  com.oplus.cota \
  com.oplus.romupdate \
  com.coloros.romupdate \
  com.oppo.ota \
  com.coloros.ota \
  com.oplus.sau \
  com.oplus.sauhelper \
  com.coloros.sau \
  com.coloros.sauhelper \
  com.coloros.assistant \
  com.heytap.assistant \
  com.opos.ads \
  com.heytap.speechassist \
  com.oplus.deepthinker
do
  enable_pkg "$PKG"
done

# Revert the most direct props. Reboot is still recommended after uninstall.
setprop persist.logd.enable 1 2>/dev/null
setprop persist.logd.logpersistd.enable 1 2>/dev/null
setprop persist.logd.flowctrl.on 1 2>/dev/null
setprop persist.logd.size 1M 2>/dev/null
setprop persist.ota.auto_download 1 2>/dev/null
setprop persist.sys.recovery_update 1 2>/dev/null
setprop persist.sys.coupdate 1 2>/dev/null
setprop persist.sys.sota.state "" 2>/dev/null
setprop sys.oplus.production.wifi.ota true 2>/dev/null
setprop persist.sys.oplus.ad_enable 1 2>/dev/null
setprop persist.sys.oplus.personalized_ad 1 2>/dev/null
setprop persist.ad.track 1 2>/dev/null
setprop persist.sys.enable_ad_logdump 1 2>/dev/null
setprop persist.sys.usage_stat_enable 1 2>/dev/null
setprop persist.oppo.collect 1 2>/dev/null
setprop persist.sys.oppo.junkmonitor true 2>/dev/null
setprop persist.sys.preload 1 2>/dev/null
setprop persist.vendor.enable.preload true 2>/dev/null
setprop persist.sys.monitor 1 2>/dev/null
setprop persist.sys.hotstart 1 2>/dev/null
setprop sys.oplus.respreload.vipcsdk.enabled true 2>/dev/null
setprop persist.sys.oplus.theia_screen_monitor.disabled 0 2>/dev/null
setprop persist.sys.fflag.override.settings_enable_monitor_phantom_procs true 2>/dev/null

rm -f "$FLAG" 2>/dev/null

# Roll back runtime feature flags/workers. Scripts may be gone or partially removed, so every step is best-effort.
rm -f "$TOUCH360_FLAG" 2>/dev/null
kill_pidfile "$TOUCH360_PID"
rm -f /data/local/tmp/aio_touch360.state 2>/dev/null
rm -rf /data/local/tmp/aio_touch360.lock 2>/dev/null

[ -f "$PERF_SCRIPT" ] && /system/bin/sh "$PERF_SCRIPT" --charge-disable >/dev/null 2>&1
[ -f "$PERF_SCRIPT" ] && /system/bin/sh "$PERF_SCRIPT" --game-disable >/dev/null 2>&1
[ -f "$PERF_SCRIPT" ] && /system/bin/sh "$PERF_SCRIPT" --shutdown-disable >/dev/null 2>&1
rm -f "${MODDIR}/bin/game_max_enabled.flag" "${MODDIR}/bin/charge_max_enabled.flag" "${MODDIR}/bin/thermal_shutdown_disable.flag" 2>/dev/null
rm -f /data/local/tmp/aio_shutdown_disable_arm 2>/dev/null
unmount_manifest_groups
rm -rf "${MODDIR}/bin/charge_max_state" "$PAYLOAD" 2>/dev/null

[ -f "$SPOOF_SCRIPT" ] && /system/bin/sh "$SPOOF_SCRIPT" --disable >/dev/null 2>&1
kill_pidfile "$COPG_CONTROLLER_PID"
rm -f "${MODDIR}/bin/game_spoof_enabled.flag" "${MODDIR}/bin/game_spoof_config.json" "${MODDIR}/bin/game_spoof_copg_compat.json" 2>/dev/null
rm -f "$SPOOF_STATE_FLAG" 2>/dev/null
rmdir "$SPOOF_STATE_DIR" /data/adb/aio_ace5 2>/dev/null
rm -f /data/local/tmp/aio_game_spoof_config.json /data/local/tmp/aio_game_spoof_copg_compat.json /data/local/tmp/aio_game_spoof_cpuinfo.txt /data/local/tmp/aio_game_spoof_copg_controller.pid 2>/dev/null
rm -f /data/local/tmp/aio_game_spoof.log 2>/dev/null
remove_aio_copg_shim

# Try to restart core services if still in same boot.
setprop ctl.start logd 2>/dev/null
setprop ctl.start update_engine 2>/dev/null

exit 0
