#!/system/bin/sh
# AIO Ace5 v3.1 — early hooks.
# Cooldown chỉ chạy khi có flag; Hiệu năng KHÔNG bind ở post-fs để tránh bootloop.

MODDIR=${0%/*}
PERF_SCRIPT="$MODDIR/bin/aio_performance.sh"
[ -f "$PERF_SCRIPT" ] && /system/bin/sh "$PERF_SCRIPT" --post-fs >/dev/null 2>&1
FLAG="$MODDIR/bin/cooldown_enabled.flag"
[ -f "$FLAG" ] || exit 0

STUB_DAEMON="$MODDIR/common/stub_daemon.sh"
STUB_CMD="$MODDIR/common/stub_cmd.sh"
LOG_FILE="/data/local/tmp/aio25_postfs.log"

_log() { printf '[%s] AIO-POSTFS: %s\n' "$(date +'%H:%M:%S' 2>/dev/null)" "$*" >> "$LOG_FILE" 2>/dev/null; }
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
write_if_writable() { [ -w "$1" ] && echo "$2" > "$1" 2>/dev/null; }

# Stop init-managed daemons first to avoid restart loop.
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

rm -rf /data/ota_package /cache/ota /data/oplus_ota /data/ota /data/update /data/.ota 2>/dev/null

write_if_writable /proc/sys/kernel/sched_schedstats 0
write_if_writable /sys/module/binder/parameters/debug_mask 0
write_if_writable /proc/sys/vm/compact_unevictable_allowed 0

exit 0
