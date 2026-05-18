#!/system/bin/sh
# AIO Ace5 v3.1 - Hiệu năng controller
# Flag-persistent Game Max / Sạc Max / Tắt shutdown bảo vệ nhiệt.
# Giữ ngưỡng giả nhiệt 29.5°C, không bind/generate ở post-fs để tránh bootloop.

_SELF="$(readlink -f "$0" 2>/dev/null)"
[ -n "$_SELF" ] || _SELF="$0"
MODDIR="${_SELF%/*}"
MODDIR="${MODDIR%/bin}"
PAYLOAD="$MODDIR/bin/extreme_gt_payload_generated"
MANIFEST="$PAYLOAD/MANIFEST"
GENERATOR="$MODDIR/bin/aio_extreme_generator.sh"
GAME_FLAG="$MODDIR/bin/game_max_enabled.flag"
CHARGE_FLAG="$MODDIR/bin/charge_max_enabled.flag"
SHUTDOWN_FLAG="$MODDIR/bin/thermal_shutdown_disable.flag"
SHUTDOWN_ARM_FILE="/data/local/tmp/aio_shutdown_disable_arm"
SHUTDOWN_ARM_TTL=120
LOG_FILE="/data/local/tmp/aio_performance.log"
CHARGE_STATE_DIR="$MODDIR/bin/charge_max_state"
CHARGE_STATE_FILE="$CHARGE_STATE_DIR/nodes.list"
AIO_LOG_HELPER="$MODDIR/bin/aio_log.sh"
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

_log(){ printf '[%s] AIO-PERF: %s\n' "$(date +'%H:%M:%S' 2>/dev/null)" "$*" >> "$LOG_FILE" 2>/dev/null; }
_snapshot_node(){
  _node="$1"
  [ -e "$_node" ] || return 0
  mkdir -p "$CHARGE_STATE_DIR" 2>/dev/null
  [ -f "$CHARGE_STATE_FILE" ] && awk -F'|' -v p="$_node" '$1==p{found=1} END{exit !found}' "$CHARGE_STATE_FILE" 2>/dev/null && return 0
  _old="$(cat "$_node" 2>/dev/null | tr '\n' ' ')"
  _perm="$(stat -c %a "$_node" 2>/dev/null || printf '')"
  printf '%s|%s|%s|%s\n' "$_node" "$_old" "$_perm" "$(_now)" >> "$CHARGE_STATE_FILE" 2>/dev/null
}
write_node(){
  _node="$1"; _val="$2"
  [ -e "$_node" ] || return 0
  _snapshot_node "$_node"
  if printf '%s\n' "$_val" > "$_node" 2>/dev/null; then return 0; fi
  _perm="$(stat -c %a "$_node" 2>/dev/null || printf '')"
  chmod u+w "$_node" 2>/dev/null
  if printf '%s\n' "$_val" > "$_node" 2>/dev/null; then
    [ -n "$_perm" ] && chmod "$_perm" "$_node" 2>/dev/null
    return 0
  fi
  [ -n "$_perm" ] && chmod "$_perm" "$_node" 2>/dev/null
  return 1
}
_write_node_log(){
  _node="$1"; _val="$2"; _tag="$3"
  [ -e "$_node" ] || return 0
  _old="$(cat "$_node" 2>/dev/null)"
  if write_node "$_node" "$_val"; then
    _new="$(cat "$_node" 2>/dev/null)"
    _log "charge-hint ${_tag:-node}: $_node ${_old:-?}->${_new:-?}"
  else
    _log "charge-hint failed ${_tag:-node}: $_node"
  fi
}
_write_votable_hint(){
  _name="$1"; _val="$2"; _active="$3"
  _d="/proc/oplus-votable/$_name"
  [ -d "$_d" ] || return 0
  _before="$(cat "$_d/status" 2>/dev/null | tr '\n' ';')"
  [ -e "$_d/force_val" ] && _write_node_log "$_d/force_val" "$_val" "votable-$_name-force-val"
  [ -e "$_d/force_active" ] && _write_node_log "$_d/force_active" "$_active" "votable-$_name-force-active"
  _after="$(cat "$_d/status" 2>/dev/null | tr '\n' ';')"
  _log "charge-votable $_name status-before=${_before:-?} status-after=${_after:-?}"
}
_setp(){ setprop "$1" "$2" 2>/dev/null; }
_mount_has(){ mount | awk -v t="$1" '$2==t{found=1} END{exit !found}' 2>/dev/null; }
_now(){ date +%s 2>/dev/null || printf '0'; }

ensure_payload(){
  _force="${1:-0}"
  [ -f "$GENERATOR" ] || { _log "generator missing"; return 1; }
  if [ "$_force" = "1" ] || [ ! -f "$MANIFEST" ]; then
    /system/bin/sh "$GENERATOR" --force >> "$LOG_FILE" 2>&1
  fi
  [ -f "$MANIFEST" ]
}

bind_file(){
  SRC="$1"; TARGET="$2"
  [ -f "$SRC" ] || { _log "skip missing src: $SRC"; return 0; }
  [ -e "$TARGET" ] || { _log "skip missing target: $TARGET"; return 0; }
  _mount_has "$TARGET" && { _log "already mounted: $TARGET"; return 0; }
  mount -o bind "$SRC" "$TARGET" 2>/dev/null && _log "bind $TARGET" || _log "bind failed $TARGET"
}

umount_file(){
  TARGET="$1"
  _mount_has "$TARGET" || return 0
  umount "$TARGET" 2>/dev/null && _log "umount $TARGET" || _log "umount failed $TARGET"
}

bind_group(){
  _group="$1"
  ensure_payload 0 || return 0
  while IFS='|' read -r g target; do
    [ "$g" = "$_group" ] || continue
    [ -n "$target" ] || continue
    bind_file "$PAYLOAD$target" "$target"
  done < "$MANIFEST"
}

unmount_group(){
  _group="$1"
  [ -f "$MANIFEST" ] || return 0
  while IFS='|' read -r g target; do
    [ "$g" = "$_group" ] || continue
    [ -n "$target" ] || continue
    umount_file "$target"
  done < "$MANIFEST"
}

log_charge_state(){
  _log "charge-state begin"
  for f in /sys/class/power_supply/*/type /sys/class/power_supply/*/status /sys/class/power_supply/*/charge_type /sys/class/power_supply/*/voltage_now /sys/class/power_supply/*/current_now /sys/class/power_supply/*/input_current_now /sys/class/power_supply/*/constant_charge_current_max; do
    [ -e "$f" ] && _log "charge-state $f=$(cat "$f" 2>/dev/null)"
  done
  _log "charge-state end"
}

apply_charge_power_hints(){
  # Không ép điện áp/dòng vượt handshake phần cứng. Chỉ mở các cờ disable/suspend/cooldown/smart/slow charging nếu node tồn tại.
  for f in /sys/class/power_supply/*/input_suspend /sys/class/power_supply/*/usb_suspend /sys/class/power_supply/*/charge_disable /sys/class/power_supply/*/charging_disable /sys/class/power_supply/*/cool_down /sys/class/power_supply/*/cooldown; do
    [ -e "$f" ] && _write_node_log "$f" 0 "clear-disable"
  done
  for f in /sys/class/power_supply/*/charging_enabled /sys/class/power_supply/*/mmi_charging_enable; do
    [ -e "$f" ] && _write_node_log "$f" 1 "enable-charge"
  done

  for base in /sys/class/oplus_chg /sys/class/oplus_chg/*; do
    [ -d "$base" ] || continue
    for n in cool_down cooldown cool_down_force_5v slow_charging_enable smart_charging_enable night_charging_enable smart_charge_enable smart_charge_user_switch charge_protection_enable input_suspend usb_suspend charge_disable charging_disable; do
      [ -e "$base/$n" ] && _write_node_log "$base/$n" 0 "oplus-clear"
    done
    for n in charging_enabled mmi_charging_enable fastchg_allow voocphy_support voocchg_ing fastchg_started; do
      [ -e "$base/$n" ] && _write_node_log "$base/$n" 1 "oplus-enable"
    done
  done

  for v in CHG_DISABLE CHARGE_DISABLE USB_SUSPEND INPUT_SUSPEND SMART_CHG_DISABLE SLOW_CHG_DISABLE COOL_DOWN COOLDOWN COOL_DOWN_VOTER; do
    _write_votable_hint "$v" 0 1
  done

  # Chỉ log các votable giới hạn dòng/điện áp để debug; không tự ép giá trị cao vì sai đơn vị có thể nguy hiểm.
  for v in FCC USB_ICL FV CHARGER_VOLTAGE CHARGER_CURRENT; do
    d="/proc/oplus-votable/$v"
    [ -d "$d" ] || continue
    _log "charge-votable-present $v force_val=$(cat "$d/force_val" 2>/dev/null) force_active=$(cat "$d/force_active" 2>/dev/null) status=$(cat "$d/status" 2>/dev/null | tr '
' ';')"
  done
  log_charge_state
}

apply_runtime(){
  WANT_GAME="$1"
  WANT_CHARGE="$2"
  t=29500
  bat_t=29500
  for tz in /sys/class/thermal/*; do
    [ -f "$tz/temp" ] || continue
    typ="$(cat "$tz/type" 2>/dev/null)"
    case "$typ" in
      pm8550_gpio03_usr|pm8550vs_g_tz|pm8550b_tz|pm8550vs_c_tz|pa-therm2-sys3|rear-tof-therm|cam-flash-therm|wlan-therm|xo-therm|oplus_thermal_ipa|board_temp|ap_ntc|ltepa_ntc|nrpa_ntc|wcn_temp|shell*)
        [ "$WANT_GAME" = "1" ] && write_node "$tz/emul_temp" "$t"
      ;;
      batt-therm|usb-therm|*batt*|*battery*|*usb*|*charger*|*chg*|*vbus*|*connector*|*charge*)
        [ "$WANT_CHARGE" = "1" ] && write_node "$tz/emul_temp" "$bat_t"
      ;;
    esac
  done

  if [ "$WANT_GAME" = "1" ]; then
    _setp persist.sys.oplus.wifi.sla.game_high_temperature 50
    _setp persist.sys.environment.temp 25
    if [ -e /proc/shell-temp ]; then
      i=0
      while [ "$i" -le 9 ]; do
        echo "$i $t" > /proc/shell-temp 2>/dev/null
        i=$((i + 1))
      done
    fi
  fi

  if [ "$WANT_CHARGE" = "1" ]; then
    _write_votable_hint GAUGE_UPDATE 1000 1
    apply_charge_power_hints
  fi
}

reset_runtime(){
  for tz in /sys/class/thermal/*; do
    [ -e "$tz/emul_temp" ] && write_node "$tz/emul_temp" 0
  done
  gu=/proc/oplus-votable/GAUGE_UPDATE
  [ -d "$gu" ] && write_node "$gu/force_active" 0
}

restore_charge_state(){
  if [ -f "$CHARGE_STATE_FILE" ]; then
    while IFS='|' read -r _node _old _perm _ts; do
      [ -e "$_node" ] || { _log "charge-restore skipped missing: $_node"; continue; }
      if [ -n "$_old" ]; then
        printf '%s\n' "$_old" > "$_node" 2>/dev/null && _log "charge-restore: $_node=$_old" || _log "charge-restore failed: $_node"
      else
        case "$_node" in
          */force_active) printf '0\n' > "$_node" 2>/dev/null ;;
          */emul_temp) printf '0\n' > "$_node" 2>/dev/null ;;
        esac
      fi
      [ -n "$_perm" ] && chmod "$_perm" "$_node" 2>/dev/null
    done < "$CHARGE_STATE_FILE"
  fi
  for tz in /sys/class/thermal/*; do
    [ -e "$tz/emul_temp" ] && printf '0\n' > "$tz/emul_temp" 2>/dev/null
  done
  gu=/proc/oplus-votable/GAUGE_UPDATE
  [ -d "$gu" ] && printf '0\n' > "$gu/force_active" 2>/dev/null
  rm -rf "$CHARGE_STATE_DIR" 2>/dev/null
}

bind_game(){ bind_group game; }
bind_charge(){ bind_group charge; bind_group thermal_policy; bind_group high_temp; }
bind_shutdown(){ bind_group high_temp; }

unmount_game(){ unmount_group game; }
unmount_charge(){ unmount_group charge; }
unmount_thermal_policy_if_unused(){ [ -f "$GAME_FLAG" ] || [ -f "$CHARGE_FLAG" ] || unmount_group thermal_policy; }
unmount_high_temp_if_unused(){ [ -f "$GAME_FLAG" ] || [ -f "$CHARGE_FLAG" ] || [ -f "$SHUTDOWN_FLAG" ] || unmount_group high_temp; }

status(){
  [ -f "$GAME_FLAG" ] && printf 'INFO_GAME_MAX=on\n' || printf 'INFO_GAME_MAX=off\n'
  [ -f "$CHARGE_FLAG" ] && printf 'INFO_CHARGE_MAX=on\n' || printf 'INFO_CHARGE_MAX=off\n'
  printf 'INFO_CHARGE_MAX_LOG=%s\n' "$LOG_FILE"
  [ -f "$SHUTDOWN_FLAG" ] && printf 'INFO_SHUTDOWN_PROTECT=disabled\n' || printf 'INFO_SHUTDOWN_PROTECT=enabled\n'
  [ -f "$SHUTDOWN_ARM_FILE" ] && printf 'INFO_SHUTDOWN_ARMED=1\n' || printf 'INFO_SHUTDOWN_ARMED=0\n'
  if [ -f "$SHUTDOWN_ARM_FILE" ]; then
    _armed="$(cat "$SHUTDOWN_ARM_FILE" 2>/dev/null | tr -cd '0-9')"
    _age=$(( $(_now) - ${_armed:-0} ))
    printf 'INFO_SHUTDOWN_ARM_AGE=%s\n' "$_age"
    printf 'INFO_SHUTDOWN_ARM_TTL=%s\n' "$SHUTDOWN_ARM_TTL"
  fi
  [ -f "$MANIFEST" ] && printf 'INFO_DYNAMIC_PAYLOAD=ready\n' || printf 'INFO_DYNAMIC_PAYLOAD=missing\n'
  [ -f "$PAYLOAD/STATS.txt" ] && sed 's/^/INFO_EXTREME_/' "$PAYLOAD/STATS.txt" 2>/dev/null
}

apply_post_fs(){
  # BOOTLOOP SAFETY: do not generate or bind performance/thermal payload in post-fs-data.
  # Vendor services are not stable enough here; service.sh will apply after sys.boot_completed.
  _log "post-fs performance apply skipped for boot safety"
  return 0
}

apply_service(){
  G=0; C=0
  [ -f "$GAME_FLAG" ] && G=1
  [ -f "$CHARGE_FLAG" ] && C=1
  if [ "$G" = "1" ] || [ "$C" = "1" ] || [ -f "$SHUTDOWN_FLAG" ]; then
    ensure_payload 0 || exit 0
  fi
  [ "$G" = "1" ] && bind_game
  [ "$C" = "1" ] && bind_charge
  [ -f "$SHUTDOWN_FLAG" ] && bind_shutdown
  if [ "$C" = "1" ]; then
    apply_runtime 0 "$C"
  fi
}

enable_game(){
  touch "$GAME_FLAG" 2>/dev/null
  ensure_payload 1
  bind_game
  printf '[OK] Game Max đã bật. FPS chỉ ép max cho game trong danh sách AIO; app thường giữ nguyên cấu hình ROM. Reboot để áp dụng đầy đủ.\n'
  status
}

disable_game(){
  rm -f "$GAME_FLAG" 2>/dev/null
  unmount_game
  unmount_thermal_policy_if_unused
  unmount_high_temp_if_unused
  [ -f "$CHARGE_FLAG" ] || reset_runtime
  printf '[OK] Game Max đã tắt. Reboot để sạch hoàn toàn overlay.\n'
  status
}

enable_charge(){
  rm -rf "$CHARGE_STATE_DIR" 2>/dev/null
  touch "$CHARGE_FLAG" 2>/dev/null
  ensure_payload 1
  bind_charge
  apply_runtime 0 1
  printf '[OK] Sạc Max đã bật. Giữ giả nhiệt 29.5°C, nới ngưỡng nhiệt sạc +5°C, mở các cờ slow/smart/cooldown/suspend nếu ROM có node, force gauge mức 1000. Không ép được nếu củ/cáp chỉ handshake USB_DCP. Reboot để áp dụng đầy đủ.\n'
  status
}

disable_charge(){
  rm -f "$CHARGE_FLAG" 2>/dev/null
  restore_charge_state
  unmount_charge
  unmount_thermal_policy_if_unused
  unmount_high_temp_if_unused
  [ -f "$GAME_FLAG" ] || reset_runtime
  rm -rf "$CHARGE_STATE_DIR" 2>/dev/null
  printf '[OK] Sạc Max đã tắt. Reboot để sạch hoàn toàn overlay.\n'
  status
}

arm_shutdown_disable(){
  if [ -f "$SHUTDOWN_ARM_FILE" ]; then
    _old="$(cat "$SHUTDOWN_ARM_FILE" 2>/dev/null | tr -cd '0-9')"
    _age=$(( $(_now) - ${_old:-0} ))
    [ -z "$_old" ] || [ "$_age" -lt 0 ] || [ "$_age" -gt "$SHUTDOWN_ARM_TTL" ] && rm -f "$SHUTDOWN_ARM_FILE" 2>/dev/null
  fi
  _ts="$(_now)"
  printf '%s\n' "$_ts" > "$SHUTDOWN_ARM_FILE" 2>/dev/null || {
    printf '[ERR] Không tạo được xác nhận bước 1 cho Shutdown nhiệt.\n'
    return 1
  }
  printf '[WARN] BƯỚC 1/2: Chuẩn bị tắt shutdown bảo vệ nhiệt. Mặc định vẫn TẮT; chỉ bật sau bước 2. Tùy chọn này có thể làm máy ít tự ngắt khi quá nóng, tăng rủi ro treo máy, hại pin hoặc hại phần cứng. Xác nhận lần 2 trong %ss nếu thật sự hiểu rủi ro.\n' "$SHUTDOWN_ARM_TTL"
  status
}

confirm_shutdown_disable(){
  [ -f "$SHUTDOWN_ARM_FILE" ] || {
    printf '[ERR] Chưa có xác nhận bước 1. Hãy bật lại công tắc và xác nhận cảnh báo trước.\n'
    status
    return 1
  }
  _armed="$(cat "$SHUTDOWN_ARM_FILE" 2>/dev/null | tr -cd '0-9')"
  _now_ts="$(_now)"
  _age=$((_now_ts - ${_armed:-0}))
  if [ -z "$_armed" ] || [ "$_age" -lt 0 ] || [ "$_age" -gt "$SHUTDOWN_ARM_TTL" ]; then
    rm -f "$SHUTDOWN_ARM_FILE" 2>/dev/null
    printf '[ERR] Xác nhận Shutdown nhiệt đã hết hạn. Hãy thao tác lại.\n'
    status
    return 1
  fi
  rm -f "$SHUTDOWN_ARM_FILE" 2>/dev/null
  touch "$SHUTDOWN_FLAG" 2>/dev/null
  unmount_group high_temp
  ensure_payload 1
  bind_shutdown
  printf '[WARN] Đã TẮT shutdown bảo vệ nhiệt sau xác nhận 2 bước. Máy có thể ít tự ngắt vì nhiệt hơn. Chỉ dùng để test ngắn hạn, tự theo dõi nhiệt thật, và tắt lại ngay sau khi test. Reboot để áp dụng chắc chắn.\n'
  status
}

enable_shutdown_disable(){
  arm_shutdown_disable
}

disable_shutdown_disable(){
  rm -f "$SHUTDOWN_FLAG" "$SHUTDOWN_ARM_FILE" 2>/dev/null
  unmount_group high_temp
  ensure_payload 1
  if [ -f "$GAME_FLAG" ] || [ -f "$CHARGE_FLAG" ]; then
    bind_group high_temp
  fi
  unmount_high_temp_if_unused
  printf '[OK] Đã bật lại logic shutdown bảo vệ nhiệt theo stock/ROM. Reboot để sạch hoàn toàn overlay cũ.\n'
  status
}

case "${1:-}" in
  --status) status ;;
  --post-fs) apply_post_fs ;;
  --service) apply_service ;;
  --game-enable)
    aio_log performance INFO START action=game state=on
    enable_game; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log performance SUMMARY done action=game state=on status=ok; else aio_log performance ERR failed action=game state=on status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --game-disable)
    aio_log performance INFO START action=game state=off
    disable_game; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log performance SUMMARY done action=game state=off status=ok; else aio_log performance ERR failed action=game state=off status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --charge-enable)
    aio_log performance INFO START action=charge state=on
    enable_charge; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log performance SUMMARY done action=charge state=on status=ok; else aio_log performance ERR failed action=charge state=on status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --charge-disable)
    aio_log performance INFO START action=charge state=off
    disable_charge; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log performance SUMMARY done action=charge state=off status=ok; else aio_log performance ERR failed action=charge state=off status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --shutdown-arm)
    aio_log performance INFO START action=shutdown_arm state=pending
    arm_shutdown_disable; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log performance SUMMARY done action=shutdown_arm state=pending status=ok; else aio_log performance ERR failed action=shutdown_arm state=pending status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --shutdown-confirm)
    aio_log performance INFO START action=shutdown_confirm state=confirm
    confirm_shutdown_disable; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log performance SUMMARY done action=shutdown_confirm state=confirm status=ok; else aio_log performance ERR failed action=shutdown_confirm state=confirm status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --shutdown-enable)
    aio_log performance INFO START action=shutdown_disable state=on
    enable_shutdown_disable; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log performance SUMMARY done action=shutdown_disable state=on status=ok; else aio_log performance ERR failed action=shutdown_disable state=on status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --shutdown-disable)
    aio_log performance INFO START action=shutdown_disable state=off
    disable_shutdown_disable; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log performance SUMMARY done action=shutdown_disable state=off status=ok; else aio_log performance ERR failed action=shutdown_disable state=off status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --regenerate) ensure_payload 1; status ;;
  *) printf '[ERR] aio_performance.sh: tham so khong hop le: %s\n' "${1:-<none>}"; exit 1 ;;
esac
