#!/system/bin/sh
# AIO Ace5 v3.1 - System quick toggles
# Bật/tắt Tuỳ chọn nhà phát triển và Gỡ lỗi USB qua `settings put global`.
# Trạng thái persistent vì lưu trực tiếp trong Android Settings DB.

_SELF="$(readlink -f "$0" 2>/dev/null)"
[ -n "$_SELF" ] || _SELF="$0"
MODDIR="${_SELF%/*}"
MODDIR="${MODDIR%/bin}"
LOG_FILE="/data/local/tmp/aio_system_toggles.log"
AIO_LOG_HELPER="$MODDIR/bin/aio_log.sh"

if [ -f "$AIO_LOG_HELPER" ]; then
  . "$AIO_LOG_HELPER"
else
  aio_log() {
    _module="$1"; _level="$2"; _event="$3"
    shift 3
    echo "[AIO] [$_module] [$_level] $_event $*"
  }
fi

_log(){ printf '[%s] AIO-SYS: %s\n' "$(date +'%H:%M:%S' 2>/dev/null)" "$*" >> "$LOG_FILE" 2>/dev/null; }

# Đọc settings key (trả về '1', '0', '' hoặc 'null'); chuẩn hoá sang 0/1.
_settings_get(){
  _ns="$1"; _key="$2"
  _v="$(settings get "$_ns" "$_key" 2>/dev/null | tr -d '\r\n ' )"
  case "$_v" in
    1) printf '1' ;;
    0) printf '0' ;;
    ''|null|NULL) printf '0' ;;
    *) printf '0' ;;
  esac
}

_settings_put(){
  _ns="$1"; _key="$2"; _val="$3"
  if settings put "$_ns" "$_key" "$_val" >/dev/null 2>&1; then
    _log "settings put $_ns $_key $_val OK"
    return 0
  fi
  _log "settings put $_ns $_key $_val FAILED"
  return 1
}

is_dev_on(){ [ "$(_settings_get global development_settings_enabled)" = "1" ]; }
is_usb_on(){ [ "$(_settings_get global adb_enabled)" = "1" ]; }

print_info(){
  if is_dev_on; then printf 'INFO_DEV_OPTIONS=on\n'; else printf 'INFO_DEV_OPTIONS=off\n'; fi
  if is_usb_on; then printf 'INFO_USB_DEBUG=on\n';  else printf 'INFO_USB_DEBUG=off\n'; fi
}

enable_devopts(){
  if is_dev_on; then
    printf '[OK] Tuỳ chọn nhà phát triển đang BẬT (không đổi).\n'
    print_info
    return 0
  fi
  if _settings_put global development_settings_enabled 1; then
    printf '[OK] Đã BẬT Tuỳ chọn nhà phát triển. Vào Cài đặt > Hệ thống > Tuỳ chọn nhà phát triển để xem menu.\n'
    print_info
    return 0
  fi
  printf '[ERR] Không thể bật Tuỳ chọn nhà phát triển. Cần quyền root/system.\n'
  print_info
  return 1
}

disable_devopts(){
  if ! is_dev_on; then
    printf '[OK] Tuỳ chọn nhà phát triển đang TẮT (không đổi).\n'
    print_info
    return 0
  fi
  if _settings_put global development_settings_enabled 0; then
    printf '[OK] Đã TẮT Tuỳ chọn nhà phát triển. Menu sẽ ẩn khỏi Cài đặt.\n'
    print_info
    return 0
  fi
  printf '[ERR] Không thể tắt Tuỳ chọn nhà phát triển.\n'
  print_info
  return 1
}

enable_usbdebug(){
  if is_usb_on; then
    printf '[OK] Gỡ lỗi USB đang BẬT (không đổi).\n'
    print_info
    return 0
  fi
  # ADB cần Developer Options bật trước (một số ROM bắt buộc).
  if ! is_dev_on; then
    _settings_put global development_settings_enabled 1
  fi
  if _settings_put global adb_enabled 1; then
    printf '[OK] Đã BẬT Gỡ lỗi USB (ADB). Khi cắm cáp lần đầu, máy sẽ hỏi xác thực vân tay RSA.\n'
    print_info
    return 0
  fi
  printf '[ERR] Không thể bật Gỡ lỗi USB. Cần quyền root/system.\n'
  print_info
  return 1
}

disable_usbdebug(){
  if ! is_usb_on; then
    printf '[OK] Gỡ lỗi USB đang TẮT (không đổi).\n'
    print_info
    return 0
  fi
  if _settings_put global adb_enabled 0; then
    printf '[OK] Đã TẮT Gỡ lỗi USB (ADB). Kết nối ADB qua cáp sẽ bị từ chối.\n'
    print_info
    return 0
  fi
  printf '[ERR] Không thể tắt Gỡ lỗi USB.\n'
  print_info
  return 1
}

case "${1:-}" in
  --info|--status) print_info ;;
  --devopts-enable)
    aio_log system INFO START action=devopts state=on
    enable_devopts; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log system SUMMARY done action=devopts state=on status=ok; else aio_log system ERR failed action=devopts state=on status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --devopts-disable)
    aio_log system INFO START action=devopts state=off
    disable_devopts; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log system SUMMARY done action=devopts state=off status=ok; else aio_log system ERR failed action=devopts state=off status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --usbdebug-enable)
    aio_log system INFO START action=usbdebug state=on
    enable_usbdebug; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log system SUMMARY done action=usbdebug state=on status=ok; else aio_log system ERR failed action=usbdebug state=on status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  --usbdebug-disable)
    aio_log system INFO START action=usbdebug state=off
    disable_usbdebug; _rc=$?
    if [ "$_rc" -eq 0 ]; then aio_log system SUMMARY done action=usbdebug state=off status=ok; else aio_log system ERR failed action=usbdebug state=off status=error rc=$_rc; fi
    exit "$_rc"
    ;;
  *)
    printf '[ERR] aio_system_toggles.sh: tham so khong hop le: %s\n' "${1:-<none>}"
    printf '[ERR] Hop le: --info | --devopts-enable | --devopts-disable | --usbdebug-enable | --usbdebug-disable\n'
    exit 1
    ;;
esac
