#!/system/bin/sh
# AIO Ace5 v3.1 service.sh
# Re-assert Cooldown và Hiệu năng sau boot nếu flag tương ứng đang bật.
# Không daemon/loop dài; script chạy một lần rồi thoát.

MODDIR=${0%/*}
PERF_SCRIPT="$MODDIR/bin/aio_performance.sh"
SPOOF_SCRIPT="$MODDIR/bin/aio_game_spoof.sh"
DEBLOAT_SCRIPT="$MODDIR/bin/debloat.sh"
FLAG="$MODDIR/bin/cooldown_enabled.flag"
TOUCH360_FLAG="$MODDIR/bin/touch_360_enabled.flag"
THERMAL_DPM_FLAG="/data/local/tmp/aio_thermal_dpm_bypass_active"
STUB_DAEMON="$MODDIR/common/stub_daemon.sh"
STUB_CMD="$MODDIR/common/stub_cmd.sh"
_SVC_TS="$(date +%Y%m%d_%H%M%S 2>/dev/null)_$$"
LOG_FILE="/data/local/tmp/aio25_service_${_SVC_TS}.log"

# Keep only recent service logs; Service still exits after one boot pass.
_i=0
for _old in /data/local/tmp/aio24_service.log /data/local/tmp/aio25_service_*.log; do
  [ -f "$_old" ] || continue
  _i=$((_i+1))
  _mt=$(stat -c %Y "$_old" 2>/dev/null || printf '0')
  [ $(( $(date +%s 2>/dev/null || printf '0') - _mt )) -gt 604800 ] && rm -f "$_old" 2>/dev/null
done

_log() { printf '[%s] AIO-SVC: %s\n' "$(date +'%H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null; }

ctl_stop() { [ -n "$1" ] && setprop ctl.stop "$1" 2>/dev/null; }
ctl_start() { [ -n "$1" ] && setprop ctl.start "$1" 2>/dev/null; }
kill_proc() { pkill -9 "$1" 2>/dev/null; killall -9 "$1" 2>/dev/null; }
_mount_has() {
  TARGET="$1"
  awk -v t="$TARGET" '$2==t{found=1} END{exit !found}' /proc/mounts 2>/dev/null || \
    mount | awk -v t="$TARGET" '$2==t{found=1} END{exit !found}' 2>/dev/null
}
bind_file() {
  SRC="$1"; TARGET="$2"; SERVICE="$3"
  [ -f "$SRC" ] || { _log "skip bind missing src: $SRC"; return 0; }
  [ -e "$TARGET" ] || { _log "skip bind missing target: $TARGET"; return 0; }
  _mount_has "$TARGET" && { _log "already mounted: $TARGET"; return 0; }
  if mount -o bind "$SRC" "$TARGET" 2>/dev/null && _mount_has "$TARGET"; then
    _log "bind ok: $TARGET"
    return 0
  fi
  umount "$TARGET" 2>/dev/null
  _log "WARN: bind failed, fallback stock service for $TARGET"
  ctl_start "$SERVICE"
  return 1
}
setp() { setprop "$1" "$2" 2>/dev/null; }
disable_pkg() {
  PKG="$1"
  pm path "$PKG" >/dev/null 2>&1 || pm list packages -u 2>/dev/null | grep -qx "package:$PKG" || return 0
  pm disable-user --user 0 "$PKG" >/dev/null 2>&1 || pm disable --user 0 "$PKG" >/dev/null 2>&1
}

_apply_touch360_late() {
  [ -f "$TOUCH360_FLAG" ] || { _log "360Hz flag not found; skip"; return 0; }
  [ -f "$DEBLOAT_SCRIPT" ] || { _log "debloat script missing; cannot restart 360Hz worker"; return 0; }
  _log "360Hz flag detected → restart worker"
  /system/bin/sh "$DEBLOAT_SCRIPT" --touch360-enable >> "$LOG_FILE" 2>&1
  _log "360Hz late stage done"
}

_apply_cooldown_late() {
  [ -f "$FLAG" ] || { _log "Cooldown flag not found; exit"; return 0; }
  _log "Cooldown flag detected → apply late stage"

  for S in logd logd-auditctl logd-reinit logcatd logpersistd update_engine update_engine_sideload otapreopt_chroot otapreopt_script; do
    ctl_stop "$S"
  done
  sleep 1

  bind_file "$STUB_DAEMON" /system/bin/logd logd
  bind_file "$STUB_CMD"    /system/bin/logcat logcatd
  bind_file "$STUB_DAEMON" /system/bin/update_engine update_engine
  bind_file "$STUB_CMD"    /system/bin/update_engine_sideload update_engine_sideload

  for P in logd logcat logpersistd update_engine update_engine_sideload otapreopt_script otapreopt_chroot otapreopt cotad romupdate smartscene preload sysmonitor hotstart; do
    kill_proc "$P"
  done

  setp persist.logd.enable 0
  setp persist.logd.logpersistd.enable 0
  setp persist.logd.flowctrl.on 0
  setp persist.logd.size 0
  setp persist.ota.auto_download 0
  setp persist.sys.recovery_update 0
  setp persist.sys.coupdate 0
  setp persist.sys.sota.state none
  setp sys.oplus.production.wifi.ota false
  setp persist.sys.oplus.ad_enable 0
  setp persist.sys.oplus.personalized_ad 0
  setp persist.ad.track 0
  setp persist.sys.enable_ad_logdump 0
  setp persist.sys.usage_stat_enable 0
  setp persist.oppo.collect 0
  setp persist.sys.oppo.junkmonitor false
  setp persist.sys.preload 0
  setp persist.vendor.enable.preload false
  setp persist.sys.monitor 0
  setp persist.sys.hotstart 0
  setp sys.oplus.respreload.vipcsdk.enabled false
  setp persist.sys.oplus.theia_screen_monitor.disabled 1
  setp persist.sys.fflag.override.settings_enable_monitor_phantom_procs false

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
    disable_pkg "$PKG"
  done

  rm -rf /data/ota_package /cache/ota /data/oplus_ota /data/ota /data/update /data/.ota 2>/dev/null
  _log "Cooldown late stage done"
}


_restore_thermal_dpm_if_needed() {
  [ -f "$THERMAL_DPM_FLAG" ] || return 0
  _log "Thermal DPM restore flag detected → restore override-status 3"
  if command -v cmd >/dev/null 2>&1; then
    cmd thermalservice override-status 3 >/dev/null 2>&1 \
      && _log "Thermal DPM restored after interrupted cleanup" \
      || _log "WARN: Thermal DPM restore command failed"
  else
    _log "WARN: cmd not found; cannot restore Thermal DPM"
  fi
  rm -f "$THERMAL_DPM_FLAG" 2>/dev/null
}

_boot_wait=0
_boot_max=120
while [ "$_boot_wait" -lt "$_boot_max" ]; do
  [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && break
  sleep 2
  _boot_wait=$((_boot_wait + 2))
done

_restore_thermal_dpm_if_needed

if [ -f "$PERF_SCRIPT" ]; then
  _log "Performance boot apply start"
  /system/bin/sh "$PERF_SCRIPT" --service >> "$LOG_FILE" 2>&1
  _log "Performance boot apply done"
fi

if [ -f "$SPOOF_SCRIPT" ]; then
  _log "Game Spoof config export start"
  /system/bin/sh "$SPOOF_SCRIPT" --service >> "$LOG_FILE" 2>&1
  _log "Game Spoof config export done"
fi

_apply_touch360_late
_apply_cooldown_late
exit 0
