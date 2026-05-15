#!/system/bin/sh
# - start horae lại

BINDIR="${0%/*}"

AIO_LOG_HELPER="$BINDIR/aio_log.sh"
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

FLAG="$BINDIR/touch_360_enabled.flag"
PID_FILE="$BINDIR/touch_360_worker.pid"

LOG_FILE="/data/local/tmp/aio_touch360_worker.log"
LOCK_DIR="/data/local/tmp/aio_touch360.lock"
STATE_FILE="/data/local/tmp/aio_touch360.state"

REAPPLY_SEC=6

NODE_GAME_SWITCH="26"
NODE_REPORT_RATE="182"
NODE_GAME_MODE="183"
NODE_HIGH_FRAME="184"

PROC_GAME_SWITCH="/proc/touchpanel/game_switch_enable"
PROC_REPORT_RATE="/proc/touchpanel/report_rate"
PROC_GAME_MODE="/proc/touchpanel/game_mode"
PROC_HIGH_FRAME="/proc/touchpanel/high_frame_enable"

log() {
  printf '%s %s\n' "$(date '+%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG_FILE" 2>/dev/null
}

is_pid_alive() {
  _pid="$1"
  [ -n "$_pid" ] || return 1
  [ "$_pid" -gt 0 ] 2>/dev/null || return 1
  kill -0 "$_pid" 2>/dev/null
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$PID_FILE" 2>/dev/null
    return 0
  fi

  _old_pid="$(cat "$PID_FILE" 2>/dev/null | tr -d ' \t\r\n')"
  if is_pid_alive "$_old_pid"; then
    log "[INFO] worker already running pid=$_old_pid"
    exit 0
  fi

  rm -rf "$LOCK_DIR" 2>/dev/null

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "$$" > "$PID_FILE" 2>/dev/null
    return 0
  fi

  log "[ERR] cannot acquire lock"
  exit 1
}

release_lock() {
  rm -f "$PID_FILE" 2>/dev/null
  rm -rf "$LOCK_DIR" 2>/dev/null
}

find_touch_cmd() {
  if command -v touchHidlTest >/dev/null 2>&1; then
    command -v touchHidlTest
    return 0
  fi

  for x in \
    /odm/bin/touchHidlTest \
    /system/bin/touchHidlTest \
    /system_ext/bin/touchHidlTest \
    /vendor/bin/touchHidlTest
  do
    if [ -x "$x" ]; then
      printf '%s\n' "$x"
      return 0
    fi
  done

  return 1
}

tw_all() {
  _node="$1"
  _val="$2"
  _bin="$(find_touch_cmd)"

  if [ -z "$_bin" ]; then
    log "[SKIP] touchHidlTest not found"
    return 1
  fi

  "$_bin" -c wo 0 "$_node" "$_val" >/dev/null 2>&1
  _rc_wo=$?
  "$_bin" -c wb 0 "$_node" "$_val" >/dev/null 2>&1
  _rc_wb=$?
  "$_bin" -c ws 0 "$_node" "$_val" >/dev/null 2>&1
  _rc_ws=$?

  log "[SET] node=$_node val=$_val rc_wo=$_rc_wo rc_wb=$_rc_wb rc_ws=$_rc_ws"

  if [ "$_rc_wo" -eq 0 ] || [ "$_rc_wb" -eq 0 ] || [ "$_rc_ws" -eq 0 ]; then
    return 0
  fi

  return 1
}

write_proc() {
  _path="$1"
  _val="$2"

  if [ -e "$_path" ]; then
    echo "$_val" > "$_path" 2>/dev/null
    _rc=$?
    log "[PROC] echo $_val > $_path rc=$_rc"
    return "$_rc"
  fi

  log "[PROC_SKIP] $_path not found"
  return 1
}

read_state() {
  _bin="$(find_touch_cmd)"

  if [ -n "$_bin" ]; then
    _r26="$("$_bin" -c ro 0 "$NODE_GAME_SWITCH" 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    _r183="$("$_bin" -c ro 0 "$NODE_GAME_MODE" 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    _r184="$("$_bin" -c ro 0 "$NODE_HIGH_FRAME" 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    _r182="$("$_bin" -c ro 0 "$NODE_REPORT_RATE" 2>&1 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    log "[RO] 26=$_r26 | 183=$_r183 | 184=$_r184 | 182=$_r182"
  fi

  for p in "$PROC_GAME_SWITCH" "$PROC_GAME_MODE" "$PROC_HIGH_FRAME" "$PROC_REPORT_RATE"; do
    if [ -e "$p" ]; then
      _v="$(cat "$p" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      log "[CAT] $p = $_v"
    fi
  done
}

stop_horae_like_original() {
  stop horae >/dev/null 2>&1
  log "[INFO] stop horae requested"
}

start_horae_restore() {
  start horae >/dev/null 2>&1
  log "[INFO] start horae requested"
}

apply_360_ultimate() {
  # Stop trước để tránh policy kéo lại.
  stop_horae_like_original

  # Bật scene/game/high-frame trước.
  tw_all "$NODE_GAME_SWITCH" 1
  tw_all "$NODE_GAME_MODE" 1
  tw_all "$NODE_HIGH_FRAME" 1
  tw_all "$NODE_REPORT_RATE" 360

  # Ghi trực tiếp proc sau cùng để đè lớp HAL.
  write_proc "$PROC_GAME_SWITCH" 1
  write_proc "$PROC_GAME_MODE" 1
  write_proc "$PROC_HIGH_FRAME" 1
  write_proc "$PROC_REPORT_RATE" 360

  echo "ultimate-force" > "$STATE_FILE" 2>/dev/null

  read_state
}

restore_default() {
  # Restore mềm.
  tw_all "$NODE_REPORT_RATE" 0
  tw_all "$NODE_HIGH_FRAME" 0
  tw_all "$NODE_GAME_MODE" 0
  tw_all "$NODE_GAME_SWITCH" 0

  write_proc "$PROC_REPORT_RATE" 0
  write_proc "$PROC_HIGH_FRAME" 0
  write_proc "$PROC_GAME_MODE" 0
  write_proc "$PROC_GAME_SWITCH" 0

  rm -f "$STATE_FILE" 2>/dev/null

  read_state
  start_horae_restore
}

cleanup_exit() {
  aio_log touch360 SUMMARY exit status=ok
  restore_default
  release_lock
  log "[INFO] worker stopped"
  exit 0
}

trap cleanup_exit INT TERM HUP

acquire_lock
aio_log touch360 INFO START worker=touch_360 reapply=${REAPPLY_SEC}s
log "[INFO] worker started mode=ultimate-force REAPPLY_SEC=$REAPPLY_SEC"

# Apply ngay khi bật switch.
apply_360_ultimate
aio_log touch360 PROGRESS apply status=ok

while [ -f "$FLAG" ]; do
  sleep "$REAPPLY_SEC"
  [ -f "$FLAG" ] || break
  apply_360_ultimate
  aio_log touch360 PROGRESS apply status=ok
done

cleanup_exit