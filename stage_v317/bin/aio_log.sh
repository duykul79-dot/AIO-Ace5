#!/system/bin/sh
# AIO Ace5 unified logging helper. Prints to stdout and appends standardized log to /sdcard/Download/report/log.txt.

AIO_REPORT_DIR_PRIMARY="/sdcard/Download/report"
AIO_REPORT_DIR_FALLBACK="/sdcard/downloads/report"
AIO_REPORT_LOG=""

aio_ts() {
  date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '0000-00-00 00:00:00'
}

aio_log_file() {
  if [ -n "$AIO_REPORT_LOG" ]; then
    echo "$AIO_REPORT_LOG"
    return 0
  fi

  if mkdir -p "$AIO_REPORT_DIR_PRIMARY" 2>/dev/null; then
    AIO_REPORT_LOG="$AIO_REPORT_DIR_PRIMARY/log.txt"
    echo "$AIO_REPORT_LOG"
    return 0
  fi

  if mkdir -p "$AIO_REPORT_DIR_FALLBACK" 2>/dev/null; then
    AIO_REPORT_LOG="$AIO_REPORT_DIR_FALLBACK/log.txt"
    echo "$AIO_REPORT_LOG"
    return 0
  fi

  return 1
}

aio_log() {
  _module="$1"
  _level="$2"
  _event="$3"
  shift 3

  _line="[$(aio_ts)] [AIO] [$_module] [$_level] $_event"
  while [ "$#" -gt 0 ]; do
    _line="$_line $1"
    shift
  done

  printf '%s\n' "$_line"

  _log_file="$(aio_log_file 2>/dev/null)"
  if [ -n "$_log_file" ]; then
    printf '%s\n' "$_line" >> "$_log_file" 2>/dev/null
  fi
}
