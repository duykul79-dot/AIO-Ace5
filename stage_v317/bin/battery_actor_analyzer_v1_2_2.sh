#!/system/bin/sh
# battery_actor_analyzer_v1_2_2.sh
# Analyze reports created by battery_input_collector_v1.sh.
# Root is NOT required to analyze an existing input file.
#
# Usage:
#   sh battery_actor_analyzer_v1.sh /sdcard/Report/battery_input_idle_YYYYMMDD_HHMMSS.txt
#   sh battery_actor_analyzer_v1.sh /sdcard/Report/battery_input_idle_YYYYMMDD_HHMMSS.txt.gz
#
# Output:
#   /sdcard/Report/battery_analysis_<input_basename>_<timestamp>.txt
#
# Design goals:
#   - No logcat.
#   - CPU-first scoring to avoid false suspects from package-name prefixes.
#   - Exact package token extraction, not prefix grep like com.android.se from com.android.server.
#   - Handles ColorOS/OPlus dumpsys sections, Android 15, KernelSU/Magisk/APatch environments.

set +e
export PATH="/system/bin:/system/xbin:/vendor/bin:/odm/bin:/product/bin:/apex/com.android.runtime/bin:$PATH"

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

VERSION="1.2.2"
IN="${1:-}"
REPORT_DIR="${REPORT_DIR:-/sdcard/Report}"

if [ -z "$IN" ] || [ "$IN" = "--help" ] || [ "$IN" = "-h" ]; then
  cat <<'EOF'
battery_actor_analyzer_v1_2_2.sh

Usage:
  sh battery_actor_analyzer_v1_2_2.sh <battery_input_collector_report.txt|txt.gz>

Example:
  sh /sdcard/battery_actor_analyzer_v1_2_2.sh /sdcard/Report/battery_input_idle_20260427_191502.txt

Output:
  /sdcard/Report/battery_analysis_<input>_<timestamp>.txt

Notes:
  This analyzer reads an existing collector report. It does not run dumpsys itself.
EOF
  exit 0
fi

aio_log battery INFO START script=battery_actor_analyzer input="$IN"
if [ ! -f "$IN" ]; then
  echo "[ERR] Input file not found: $IN"
  aio_log battery ERR failed script=battery_actor_analyzer status=error reason=input_missing
  exit 1
fi

mkdir -p "$REPORT_DIR" 2>/dev/null
# Fallback if /sdcard/Report is not writable, useful when testing outside Android.
_TEST_FILE="${REPORT_DIR}/.write_test_$$"
touch "$_TEST_FILE" >/dev/null 2>&1
if [ ! -f "$_TEST_FILE" ]; then
  REPORT_DIR="$(dirname "$IN")"
else
  rm -f "$_TEST_FILE" 2>/dev/null
fi
TS="$(date +%Y%m%d_%H%M%S 2>/dev/null)"
[ -n "$TS" ] || TS="$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}')"
BASE="$(basename "$IN")"
BASE="${BASE%.gz}"
BASE="${BASE%.txt}"
OUT="${REPORT_DIR}/battery_analysis_${BASE}_${TS}.txt"
TMPDIR="/data/local/tmp/batt_actor_${TS}_$$"
mkdir -p "$TMPDIR" 2>/dev/null || TMPDIR="/tmp/batt_actor_${TS}_$$"
mkdir -p "$TMPDIR" 2>/dev/null

PLAIN="$TMPDIR/input.txt"
EVENTS="$TMPDIR/events.tsv"
UIDMAP="$TMPDIR/uidmap.tsv"
SCORES="$TMPDIR/scores.tsv"
SYMPTOMS="$TMPDIR/symptoms.tsv"
AGGREGATES="$TMPDIR/aggregates.tsv"

have() { command -v "$1" >/dev/null 2>&1; }

case "$IN" in
  *.gz)
    if have gzip; then gzip -dc "$IN" > "$PLAIN" 2>/dev/null
    elif have busybox; then busybox gzip -dc "$IN" > "$PLAIN" 2>/dev/null
    else echo "[ERR] gzip input but gzip/busybox not found"; exit 1
    fi
    ;;
  *) cp "$IN" "$PLAIN" 2>/dev/null ;;
esac

if [ ! -s "$PLAIN" ]; then
  echo "[ERR] Cannot read/decompress input: $IN"
  exit 1
fi

extract_first() {
  # $1 regex
  grep -m1 -E "$1" "$PLAIN" 2>/dev/null | sed 's/^[[:space:]]*//'
}

mode="$(grep -m1 '^mode=' "$PLAIN" 2>/dev/null | cut -d= -f2-)"
collector_ver="$(grep -m1 '^version=' "$PLAIN" 2>/dev/null | cut -d= -f2-)"
generated="$(awk 'NR<=8 && /^[A-Z][a-z][a-z] /{print; exit}' "$PLAIN" 2>/dev/null)"
device="$(awk '/^--- BEGIN BUILD \/ DEVICE \/ ROM ---/{f=1;next}/^--- END BUILD \/ DEVICE \/ ROM/{f=0}f{a[++n]=$0}END{print a[6]}' "$PLAIN" 2>/dev/null)"
rom="$(awk '/^--- BEGIN BUILD \/ DEVICE \/ ROM ---/{f=1;next}/^--- END BUILD \/ DEVICE \/ ROM/{f=0}f{a[++n]=$0}END{print a[5]}' "$PLAIN" 2>/dev/null)"
sdk="$(awk '/^--- BEGIN BUILD \/ DEVICE \/ ROM ---/{f=1;next}/^--- END BUILD \/ DEVICE \/ ROM/{f=0}f{a[++n]=$0}END{print a[2]}' "$PLAIN" 2>/dev/null)"

battery_status="$(awk '/===== BATTERY DUMPSYS =====/{s=1;next}/^===== /&&s{exit}s&&/status:/{print $2; exit}' "$PLAIN" 2>/dev/null)"
battery_level="$(awk '/===== BATTERY DUMPSYS =====/{s=1;next}/^===== /&&s{exit}s&&/level:/{print $2; exit}' "$PLAIN" 2>/dev/null)"
battery_temp_raw="$(awk '/===== BATTERY DUMPSYS =====/{s=1;next}/^===== /&&s{exit}s&&/temperature:/{print $2; exit}' "$PLAIN" 2>/dev/null)"
phone_temp_raw="$(awk '/===== BATTERY DUMPSYS =====/{s=1;next}/^===== /&&s{exit}s&&/PhoneTemp:/{print $2; exit}' "$PLAIN" 2>/dev/null)"
capacity="$(grep -m1 'Estimated battery capacity:' "$PLAIN" 2>/dev/null | sed -E 's/.*Estimated battery capacity:[[:space:]]*([0-9.]+).*/\1/')"
time_on_batt="$(grep -m1 'Time on battery:' "$PLAIN" 2>/dev/null | sed 's/^[[:space:]]*//')"
time_screen_off="$(grep -m1 'Time on battery screen off:' "$PLAIN" 2>/dev/null | sed 's/^[[:space:]]*//')"
actual_drain="$(grep -m1 'Computed drain:' "$PLAIN" 2>/dev/null | sed 's/^[[:space:]]*//')"
screen_on_amount="$(grep -m1 'Amount discharged while screen on:' "$PLAIN" 2>/dev/null | sed 's/^[[:space:]]*//')"
screen_off_amount="$(grep -m1 'Amount discharged while screen off:' "$PLAIN" 2>/dev/null | sed 's/^[[:space:]]*//')"

# Build package UID map.
awk '
/^===== PACKAGE UID MAP =====$/ { in_uidmap=1; next }
/^===== / && in_uidmap { in_uidmap=0 }
!in_uidmap { next }
/package:[^[:space:]]+[[:space:]]+uid:[0-9]+/ {
  pkg=$0
  sub(/^.*package:/,"",pkg)
  sub(/[[:space:]].*$/,"",pkg)
  uid=$0
  sub(/^.*uid:/,"",uid)
  sub(/[^0-9].*$/,"",uid)
  if (pkg != "" && uid != "") print uid "\t" pkg
  next
}
/^[A-Za-z0-9_.-]+[[:space:]]+[0-9]+[[:space:]]/ {
  # Supports /data/system/packages.list snapshots collected by collector v1.1+
  pkg=$1; uid=$2
  if (pkg ~ /^(com|org|net|io|me|tv|app|cn|jp|kr|de|ru|vendor|android)\./ && uid ~ /^[0-9]+$/) print uid "\t" pkg
}
' "$PLAIN" | sort -u > "$UIDMAP"

# Generate event stream. Columns:
# actor metric value detail
awk -v UIDMAP="$UIDMAP" '
BEGIN {
  while ((getline line < UIDMAP) > 0) {
    split(line, a, "\t")
    uid=a[1]; pkg=a[2]
    if (uid == "" || pkg == "") continue
    key=uid "\t" pkg
    if (seen_uid_pkg[key]++) continue
    installed[pkg]=1
    installed_count++
    uidpkg_count[uid]++
    if (uidpkg_count[uid] == 1) uidpkg_first[uid]=pkg
    else uidpkg_first[uid]=""
  }
  close(UIDMAP)
}

function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s}
function strip_punct(s){
  gsub(/^[<({[]+/,"",s)
  gsub(/[]>)};,]+$/,"",s)
  gsub(/^ComponentInfo[{]/,"",s)
  return s
}
function uid_to_num(u, x, p) {
  u=tolower(strip_punct(u))
  gsub(/^[^0-9u]*/,"",u)
  gsub(/[^0-9a-z].*$/,"",u)
  if (u ~ /^u[0-9]+a[0-9]+$/) {
    x=u
    sub(/^u/,"",x)
    split(x,p,"a")
    return p[1]*100000 + 10000 + p[2]
  }
  if (u ~ /^[0-9]+$/) return u+0
  return ""
}
function actor_from_uid(u, uid) {
  uid=uid_to_num(u)
  if (uid == "") return ""
  if (uid == 1000) return "android/system"
  if (uid == 1001) return "radio/system"
  if (uidpkg_count[uid] == 1 && uidpkg_first[uid] != "") return uidpkg_first[uid]
  return "uid/" uid
}
function installed_prefix(t,    p,n,i,j,pref) {
  if (t in installed) return t
  n=split(t, p, ".")
  for (i=n-1; i>=2; i--) {
    j=1; pref=p[1]
    while (++j<=i) pref=pref "." p[j]
    if (pref in installed) return pref
  }
  return ""
}
function known_root(t) {
  if (t == "android") return "android/system_context"
  if (t ~ /^com\.android\.server(\.|$)/) return "android/system"
  if (t ~ /^android\.uid\.systemui(\.|$)/) return "com.android.systemui"
  if (t ~ /^android\.uid\.system(\.|$)/) return "android/system"
  if (t ~ /^com\.oplus\.systemui(\.|$)/) return "com.android.systemui"
  if (t ~ /^com\.android\.systemui(\.|$)/) return "com.android.systemui"
  if (t ~ /^com\.google\.android\.gms(\.|:|$)/) return "com.google.android.gms"
  if (t ~ /^com\.google\.android\.gm(\.|:|$)/) return "com.google.android.gm"
  if (t ~ /^com\.google\.android\.inputmethod\.latin(\.|:|$)/) return "com.google.android.inputmethod.latin"
  if (t ~ /^org\.telegram\.messenger(\.|:|$)/) return "org.telegram.messenger"
  if (t ~ /^com\.facebook\.orca(\.|:|$)/) return "com.facebook.orca"
  if (t ~ /^com\.facebook\.video\.heroplayer(\.|:|$)/) return "com.facebook.orca"
  if (t ~ /^com\.oplus\.nas(\.|:|$)/) return "com.oplus.nas"
  if (t ~ /^com\.oplus\.gesture(\.|:|$)/) return "com.oplus.gesture"
  if (t ~ /^com\.oplus\.battery(\.|:|$)/) return "com.oplus.battery"
  if (t ~ /^com\.oplus\.nhs(\.|:|$)/) return "com.oplus.nhs"
  if (t ~ /^com\.oplus\.midas(\.|:|$)/) return "com.oplus.midas"
  if (t ~ /^com\.oplus\.metis(\.|:|$)/) return "com.oplus.metis"
  if (t ~ /^com\.oplus\.aiunit(\.|:|$)/) return "com.oplus.aiunit"
  if (t ~ /^com\.oplus\.powermonitor(\.|:|$)/) return "com.oplus.powermonitor"
  if (t ~ /^com\.oplus\.athena(\.|:|$)/) return "com.oplus.athena"
  if (t ~ /^com\.oplus\.olc(\.|:|$)/) return "com.oplus.olc"
  if (t ~ /^com\.oplus\.exsystemservice(\.|:|$)/) return "com.oplus.exsystemservice"
  if (t ~ /^com\.heytap\.mcs(\.|:|$)/) return "com.heytap.mcs"
  if (t ~ /^com\.heytap\.accessory(\.|:|$)/) return "com.heytap.accessory"
  if (t ~ /^com\.coloros\.sceneservice(\.|:|$)/) return "com.coloros.sceneservice"
  if (t ~ /^com\.coloros\.assistantscreen(\.|:|$)/) return "com.coloros.assistantscreen"
  if (t ~ /^com\.android\.launcher(\.|:|$)/) return "com.android.launcher"
  if (t ~ /^com\.android\.vending(\.|:|$)/) return "com.android.vending"
  if (t ~ /^com\.android\.nfc(\.|:|$)/) return "com.android.nfc"
  if (t ~ /^com\.android\.phone(\.|:|$)/) return "com.android.phone"
  if (t ~ /^com\.android\.media\.audio(\.|:|$)/) return "android.media/audio"
  return ""
}
function strip_class_suffix(t,    n,a,i,out) {
  n=split(t,a,".")
  out=a[1]
  for (i=2;i<=n;i++) {
    if (a[i] ~ /^[A-Z]/) break
    out=out "." a[i]
  }
  return out
}
function strip_label(t, lt) {
  lt=tolower(t)
  if (lt ~ /^package[:=]/) return substr(t,9)
  if (lt ~ /^pkg=/) return substr(t,5)
  if (lt ~ /^owningpackage=/) return substr(t,15)
  if (lt ~ /^procname=/) return substr(t,10)
  if (lt ~ /^packagename:/) return substr(t,13)
  if (lt ~ /^callingpackage:/) return substr(t,16)
  if (lt ~ /^sourcepackage:/) return substr(t,15)
  if (lt ~ /^tgtpkg=/) return substr(t,8)
  if (lt ~ /^targetpackage=/) return substr(t,15)
  return t
}
function root_actor(s, t, lt, kr, ip, t2) {
  t=strip_punct(s)
  t=strip_label(t)
  if (t ~ /^([0-9]+|u[0-9]+a[0-9]+):[A-Za-z0-9_.-]+$/) sub(/^[^:]+:/,"",t)
  sub(/[\/].*$/,"",t)
  sub(/:.*/,"",t)
  if (t == "android") return "android/system_context"
  if (t ~ /^uid\/[0-9]+$/) return t
  if (t in installed) return t

  kr=known_root(t)
  if (kr!="") return kr

  if (t ~ /^(com|org|net|io|me|tv|app|cn|jp|kr|de|ru|vendor|android|bin)\.[A-Za-z0-9_.-]+$/) {
    if (t ~ /^(android\.sensor|qti\.sensor|qti_sensor)$/) return ""
    ip=installed_prefix(t)
    if (ip != "") return ip
    t2=strip_class_suffix(t)
    kr=known_root(t2)
    if (kr!="") return kr
    if (installed_count == 0 && t2 ~ /^(com|org|net|io|me|tv|app|cn|jp|kr|de|ru|bin)\.[A-Za-z0-9_.-]+$/) return t2
    if (t ~ /^vendor\./ || t ~ /^android\.hardware\./) return t
    return ""
  }
  if (t ~ /^(system_server|surfaceflinger|audioserver|mediaserver|cameraserver|statsd|ostatsd|ostats_pullerd|midasd|thermal-engine-v2|crtc_commit|kgsl_hwsched|gmu_f2h|collector_top_sampler|collector_input_collector|android\.hardware\.[A-Za-z0-9_.-]+)$/) return t
  if (t ~ /^vendor\.[A-Za-z0-9_.-]+$/) return t
  return ""
}
function emit(actor, metric, value, detail) {
  actor=root_actor(actor)
  if (actor == "") return 0
  if (actor ~ /^(top|head|tail|grep|awk|sed|sh|bash|toybox|timeout|cat|battery_actor_analyzer|battery_input_collector)$/) return 0
  gsub(/\t/," ",detail)
  print actor "\t" metric "\t" value "\t" detail
  return 1
}
function emit_pkg_tokens(line, metric, value, detail,    n,i,tok,low,actor,tmp,count,a) {
  count=0
  n=split(line, a, /[[:space:]]+/)
  for (i=1; i<=n; i++) {
    tok=a[i]
    gsub(/^[^A-Za-z0-9_.:={}-]+/,"",tok)
    gsub(/[^A-Za-z0-9_.:={},-]+$/,"",tok)
    gsub(/[}]$/,"",tok)
    low=tolower(tok)
    actor=root_actor(tok)
    if (actor != "") {
      count += emit(actor, metric, value, detail)
      continue
    }
    if (low ~ /^(package|pkg|owningpackage|procname|packagename|callingpackage|sourcepackage|tgtpkg|targetpackage):?=?$/ && i<n) {
      count += emit(a[i+1], metric, value, detail)
      continue
    }
    tmp=tok
    if (match(tmp, /(com|org|net|io|me|tv|app|cn|jp|kr|de|ru|vendor|android|bin)\.[A-Za-z0-9_.:-]+/)) {
      tmp=substr(tmp, RSTART, RLENGTH)
      count += emit(tmp, metric, value, detail)
    }
  }
  return count
}
function emit_uid_tokens(line, metric, value, detail,    n,i,tok,low,u,actor,count,a) {
  count=0
  n=split(line, a, /[[:space:]]+/)
  for (i=1; i<=n; i++) {
    tok=strip_punct(a[i])
    low=tolower(tok)
    u=""
    if (low ~ /uid[:=]/) {
      u=low
      sub(/^.*uid[:=][[:space:]]*/,"",u)
    } else if ((low == "uid" || low == "uid:" || low == "uid=") && i<n) {
      u=tolower(a[i+1])
    } else if (low ~ /^u[0-9]+a[0-9]+:?$/) {
      u=low
    }
    if (u != "") {
      gsub(/[^0-9a-z].*$/,"",u)
      actor=actor_from_uid(u)
      if (actor != "") count += emit(actor, metric, value, detail)
    }
  }
  return count
}
function emit_actors(line, metric, value, detail, n) {
  n=emit_pkg_tokens(line, metric, value, detail)
  if (n == 0) n += emit_uid_tokens(line, metric, value, detail)
  return n
}
function join_fields(start,    i,s) {
  s=""
  for (i=start; i<=NF; i++) s=s (s==""?"":" ") $i
  return s
}
function cpu_num(x) {
  gsub(/%/,"",x)
  if (x ~ /^[0-9]+(\.[0-9]+)?$/) return x+0
  return -1
}
function section_name(line) {
  sub(/^===== /,"",line)
  sub(/ =====$/,"",line)
  return line
}
function times_count(line, x) {
  if (match(line, /[0-9]+[[:space:]]+times/)) {
    x=substr(line, RSTART, RLENGTH)
    sub(/[[:space:]].*$/,"",x)
    return x+0
  }
  return 1
}
function wakeups_count(line, x) {
  if (match(line, /[0-9]+[[:space:]]+wakeups/)) {
    x=substr(line, RSTART, RLENGTH)
    sub(/[[:space:]].*$/,"",x)
    return x+0
  }
  return 0
}
function sensor_weight(line, x) {
  if (match(line, /samplingPeriod=[0-9]+us/)) {
    x=substr(line, RSTART, RLENGTH)
    sub(/^samplingPeriod=/,"",x)
    sub(/us$/,"",x)
    if (x+0 <= 20000) return 3
    if (x+0 <= 66667) return 2
  }
  return 1
}

# Section tracking.
(/^===== .+ =====$/) { sec=section_name($0); next }
length($0) > 4000 { next }

# CPU process table.
sec=="CPU TOP PROCESS SAMPLES" && $1 ~ /^[0-9]+$/ && NF>=12 {
  c=cpu_num($9)
  if (c >= 0) {
    raw=join_fields(12)
    actor=raw
    if (raw ~ /battery_input_collector/) actor="collector_input_collector"
    else if (raw ~ /(^|[[:space:]])top([[:space:]]|$)|(^|[[:space:]])head([[:space:]]|$)|timeout .*top|sh -c top/) actor="collector_top_sampler"
    emit(actor, "cpu", c, "top_process")
    emit(actor, "running_context", 1, "top_process")
  }
}

# CPU thread table. Process starts at field 13 in Android top -H.
sec=="CPU TOP THREAD SAMPLES" && $1 ~ /^[0-9]+$/ && NF>=13 {
  c=cpu_num($9)
  if (c >= 0) {
    actor=join_fields(13)
    if (actor ~ /^(top|head|timeout|sh|bash)$/) actor="collector_top_sampler"
    emit(actor, "thread_cpu", c, "thread=" $12)
    emit(actor, "running_context", 1, "top_thread")
  }
}

# Process list presence is context only.
(sec=="PROCESS LIST DEFAULT" || sec=="PROCESS LIST EXTENDED") && NF>=2 {
  actor=$NF
  emit(actor, "running_context", 1, "ps")
}

# Batterystats estimated mAh UID lines.
sec=="BATTERYSTATS SUMMARY CHARGED" && $0 ~ /^[[:space:]]+UID[[:space:]]+/ && ($0 ~ /cpu=/ || $0 ~ /screen=/ || $0 ~ /wakelock=/ || $0 ~ /sensors=/) {
  uidtok=$2; sub(/:/,"",uidtok)
  mah=$3; sub(/:/,"",mah)
  actor=actor_from_uid(uidtok)
  if (mah ~ /^[0-9]+(\.[0-9]+)?$/ && actor != "") emit(actor, "mah", mah+0, "batterystats_uid_" uidtok)
  if (actor != "" && $0 ~ /wakelock=/) emit(actor, "wakelock", 1, "batterystats_uid_" uidtok)
  if (actor != "" && $0 ~ /sensors=/) emit(actor, "sensor", 1, "batterystats_uid_" uidtok)
}

# Batterystats package hints and actual wakeup alarm summaries.
sec=="BATTERYSTATS SUMMARY CHARGED" {
  low=tolower($0)
  if (low ~ /wake.?lock/) emit_actors($0, "wakelock", 1, "batterystats")
  if (low ~ /sensor/) emit_actors($0, "sensor", 1, "batterystats")
  if (low ~ /job/) emit_actors($0, "job", 1, "batterystats")
  if (low ~ /wakeup alarm|wakeups/) emit_actors($0, "alarm_wakeup", times_count($0), "batterystats_wakeup_alarm")
  else if (low ~ /alarm/) emit_actors($0, "alarm_scheduled", 1, "batterystats_alarm_context")
  if (low ~ /audio|video/) emit_actors($0, "media_context", 1, "batterystats_media_context")
}

# Foreground/activity services.
sec=="ACTIVITY FOREGROUND SERVICES / SERVICES" {
  low=tolower($0)
  if (low ~ /foreground|fg-service|startforeground|service record|servicerecord|package=/) emit_actors($0, "fg_service", 1, "activity_services")
}

# Jobs: only ready/running/executing jobs score; queued jobs are context.
sec=="JOBSCHEDULER" {
  low=tolower($0)
  if (low ~ /pkg=|owningpackage=|source:|service:|job /) {
    if (low ~ /ready: true|running|started|executing|active/) emit_actors($0, "job", 2, "jobscheduler_active")
    else emit_actors($0, "job_context", 1, "jobscheduler_context")
  }
}

# Alarms: pending alarms are context; fired/top wakeups are evidence.
sec=="ALARMS" {
  low=tolower($0)
  if (low ~ /[0-9]+ wakeups/) {
    w=wakeups_count($0)
    if (w > 0) emit_actors($0, "alarm_wakeup", w, "alarm_wakeup_count")
    else emit_actors($0, "alarm_scheduled", 1, "alarm_top_context")
  } else if (low ~ /pending alarms|next wakeup alarm|next non-wakeup alarm|elapsed_wakeup|rtc_wakeup|elapsed #|rtc #/) {
    emit_actors($0, "alarm_scheduled", 1, "alarm_pending_context")
  } else if (low ~ /procname=|componentinfo|action /) {
    emit_actors($0, "alarm_scheduled", 1, "alarm_context")
  }
}

# Device idle allowlists and active UIDs are context only.
sec=="DEVICE IDLE" || sec=="POWER EXEMPTION / TEMP ALLOWLIST" {
  low=tolower($0)
  if (low ~ /allow|whitelist|temp|except|active|idle/) emit_actors($0, "idle_allow_context", 1, "deviceidle")
}

# Location.
sec=="LOCATION" || sec=="GNSS / GPS" {
  low=tolower($0)
  if (low ~ /location|provider|request|receiver|listener|gps|gnss|throttling|allow|package|uid/) emit_actors($0, "location", 1, "location")
}

# Sensors: score active registrations, keep removals/history as context.
sec=="SENSOR SERVICE" {
  low=tolower($0)
  if (low ~ /[[:space:]][+][[:space:]]+0x|package=.*samplingperiod=|active.*package=|connection/) {
    emit_actors($0, "sensor", sensor_weight($0), "sensorservice_active")
  } else if (low ~ /[[:space:]][-][[:space:]]+0x|recent sensor events|sensor/) {
    emit_actors($0, "sensor_context", 1, "sensorservice_context")
  }
}

# Power wakelocks / proxy wake locks.
sec=="POWER / WAKELOCK" {
  low=tolower($0)
  if (low ~ /wake.?lock|packagename:|proxy uid|uid[:=]|uid /) emit_actors($0, "wakelock", 1, "power")
}

# Network stats are cumulative/context-only until collector provides before/after deltas.
# Skip these sections entirely for now to avoid false-positive idle scoring.
sec=="NETWORK STATS" || sec=="CONNECTIVITY" || sec=="WIFI FULL" || sec=="WIFI SCANNING" {
  next
}

# Media/audio.
sec=="AUDIO" || sec=="MEDIA AUDIO FLINGER" || sec=="MEDIA SESSION" {
  low=tolower($0)
  if (low ~ /active.*(play|record|session|player|track)|state=.*active|isactive=true|started|playing|recording|starttime|active player|active session/) {
    emit_actors($0, "media", 1, "audio_active")
  } else if (low ~ /audio|session|player|track|uid|package|active/) {
    emit_actors($0, "media_context", 1, "audio_context")
  }
}

# Content sync and account.
sec=="CONTENT SYNC" || sec=="ACCOUNT" {
  low=tolower($0)
  if (low ~ /activesync|syncmanager active|pending operation currently active|currently active.*sync|active.*sync/) {
    emit_actors($0, "sync", 1, "sync_active")
  } else if (low ~ /issyncable=true/ && low ~ /active|current/) {
    emit_actors($0, "sync", 1, "sync_active")
  } else if (low ~ /sync|account|provider|package|uid/) {
    emit_actors($0, "sync_context", 1, "sync_context")
  }
}

# Quick suspect status and AppOps permission lines are context only.
sec=="OPLUS / COLOROS SUSPECT PACKAGE QUICK STATUS" {
  if ($0 ~ /^--- [A-Za-z0-9_.:-]+ ---$/) {
    p=$0; gsub(/^--- /,"",p); gsub(/ ---$/,"",p)
    emit(p, "watched_pkg_context", 1, "quick_status")
  }
  low=tolower($0)
  if (low ~ /run_in_background: allow|run_any_in_background: allow|wake_lock: allow|access_fine_location: allow|activity_recognition: allow/) {
    emit_actors($0, "permission_context", 1, "appops")
  }
}
' "$PLAIN" > "$EVENTS"

# Aggregate scores.
awk -v MODE="$mode" '
BEGIN {
  FS="\t"; OFS="\t"
}
function cap(v,m){ return (v>m?m:v) }
function is_live_symptom_actor(a) {
  return (a ~ /^(system_server|surfaceflinger|com\.android\.systemui|com\.android\.launcher|vendor\.qti\.hardware\.display.*|android\.hardware\.graphics.*|android\.hardware\.composer.*|crtc_commit|kgsl_hwsched|gmu_f2h|collector_.*|com\.google\.android\.inputmethod\.latin|com\.sohu\.inputmethod\.sogouoem|com\.baidu\.input_oppo|com\.oplus\.securitykeyboard|bin\.mt\.plus\.canary|bin\.mt\.termex|com\.termux|jackpal\.androidterm)$/)
}
function is_aggregate_actor(a) {
  return (a ~ /^(android|android\/system|android\/system_context|uid\/1000|radio\/system|system_server|surfaceflinger|com\.android\.systemui|com\.android\.launcher|android\.hardware\..*|vendor\.qti\.hardware\.display.*|crtc_commit|kgsl_hwsched|gmu_f2h|collector_.*|uid\/[0-9]+)$/)
}
{
  actor=$1; metric=$2; val=$3+0; detail=$4
  if (actor == "") next
  actors[actor]=1
  if (metric=="cpu") { cpu_sum[actor]+=val; cpu_n[actor]++; if (val>cpu_max[actor]) cpu_max[actor]=val }
  else if (metric=="thread_cpu") { th_sum[actor]+=val; th_n[actor]++; if (val>th_max[actor]) th_max[actor]=val }
  else if (metric=="mah") { mah[actor]+=val }
  else if (metric=="running_context") { running[actor]+=val }
  else if (metric=="job") { job[actor]+=val }
  else if (metric=="job_context") { job_context[actor]+=val }
  else if (metric=="alarm_scheduled") { alarm_scheduled[actor]+=val }
  else if (metric=="alarm_wakeup") { alarm_wakeup[actor]+=val }
  else if (metric=="sensor") { sensor[actor]+=val }
  else if (metric=="sensor_context") { sensor_context[actor]+=val }
  else if (metric=="location") { location[actor]+=val }
  else if (metric=="wakelock") { wakelock[actor]+=val }
  else if (metric=="fg_service") { fg[actor]+=val }
  else if (metric=="media") { media[actor]+=val }
  else if (metric=="media_context") { media_context[actor]+=val }
  else if (metric=="sync") { sync[actor]+=val }
  else if (metric=="sync_context") { sync_context[actor]+=val }
  else if (metric=="idle_allow_context") { idleallow[actor]+=val }
  else if (metric=="watched_pkg_context") { watched[actor]+=val }
  else if (metric=="permission_context") { perms[actor]+=val }
}
END {
  for (a in actors) {
    avgcpu = cpu_n[a] ? cpu_sum[a]/cpu_n[a] : 0
    avgth = th_n[a] ? th_sum[a]/th_n[a] : 0
    cmax = cpu_max[a]+0
    tmax = th_max[a]+0
    mahv = mah[a]+0
    runv = running[a]+0
    jobv = job[a]+0
    schedv = alarm_scheduled[a]+0
    wakev = alarm_wakeup[a]+0
    sensorv = sensor[a]+0
    locv = location[a]+0
    wlv = wakelock[a]+0
    fgv = fg[a]+0
    mediav = media[a]+0
    syncv = sync[a]+0
    watchedv = watched[a]+0
    allowv = idleallow[a]+0
    mediactxv = media_context[a]+0
    syncctxv = sync_context[a]+0
    sensorctxv = sensor_context[a]+0

    live_score = cmax * 3.0 + avgcpu * 1.2 + tmax * 1.2 + avgth * 0.5

    idle_score = 0
    idle_score += mahv * 2.0
    idle_score += cap(wlv, 25) * 2.0
    idle_score += cap(wakev, 25) * 1.8
    idle_score += cap(jobv, 40) * 0.55
    idle_score += cap(sensorv, 25) * 1.5
    idle_score += cap(locv, 10) * 3.0
    idle_score += cap(fgv, 25) * 0.7

    symptom = is_live_symptom_actor(a) ? 1 : 0
    agg = is_aggregate_actor(a) ? 1 : 0
    reason="background"

    if (MODE == "idle") {
      if (agg) {
        score = 0
        reason = "Aggregate/system context"
      } else if (symptom && idle_score < 4.0) {
        score = 0
        reason = "Post-wake/live CPU symptom"
      } else {
        score = idle_score + (symptom ? live_score * 0.05 : live_score * 0.18)
      }
      if (reason == "background") {
        if (wlv >= 5) reason="Wakelock"
        else if (wakev >= 3) reason="Wakeup alarm"
        else if (sensorv >= 5) reason="Sensor"
        else if (locv >= 2) reason="Location"
        else if (jobv >= 10) reason="Job/sync"
        else if (fgv >= 6) reason="Foreground service"
        else if (mahv >= 1) reason="Batterystats mAh"
        else if (cmax >= 20) reason="Live CPU after wake"
      }
    } else {
      score = live_score + idle_score * 0.65
      if (cmax >= 15) reason="CPU live"
      else if (tmax >= 15) reason="Thread CPU"
      else if (mahv >= 5) reason="Batterystats mAh"
      else if (wlv >= 3) reason="Wakelock"
      else if (wakev >= 3) reason="Wakeup alarm"
      else if (sensorv >= 4) reason="Sensor"
      else if (locv >= 3) reason="Location"
      else if (jobv >= 10) reason="Job/sync"
      else if (fgv >= 5) reason="Foreground service"
    }

    printf "%.3f\t%s\t%s\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%.3f\t%.3f\t%d\t%d\t%d\t%d\t%d\n", \
      score, a, reason, cmax, avgcpu+0, tmax, mahv, \
      runv, jobv, schedv, wakev, sensorv, locv, wlv, fgv, mediav, syncv, 0, watchedv, allowv, idle_score+0, live_score+0, symptom, agg, mediactxv, syncctxv, sensorctxv
  }
}
' "$EVENTS" | sort -nr > "$SCORES"

awk -F'\t' '$23+0==1 && ($4+0>0 || $6+0>0){print $22 "\t" $0}' "$SCORES" | sort -nr | cut -f2- > "$SYMPTOMS"
awk -F'\t' '$24+0==1{print $22 "\t" $0}' "$SCORES" | sort -nr | cut -f2- > "$AGGREGATES"

top_actor="$(awk -F'\t' '$1+0>0 && $24+0==0{print $2; exit}' "$SCORES")"
top_reason="$(awk -F'\t' '$1+0>0 && $24+0==0{print $3; exit}' "$SCORES")"
top_score="$(awk -F'\t' '$1+0>0 && $24+0==0{print $1; exit}' "$SCORES")"
if [ -z "$top_actor" ]; then
  aggregate_only="$(awk -F'\t' '$24+0==1{print "yes"; exit}' "$SCORES")"
  if [ "$aggregate_only" = "yes" ]; then
    top_reason="only aggregate/system evidence found"
  fi
fi

# Quality estimation.
quality="unknown"
quality_note="Không đủ dữ liệu đánh giá chất lượng mẫu."
if echo "$battery_status" | grep -qi '3\|Discharging'; then
  quality="usable"
  quality_note="Máy đang xả pin, có thể phân tích."
fi
if echo "$time_screen_off" | grep -q 'screen off'; then
  quality="good"
  quality_note="Có dữ liệu screen-off trong batterystats."
fi
if [ "$mode" = "idle" ]; then
  quality="${quality}-idle"
fi

uidmap_count="$(wc -l < "$UIDMAP" 2>/dev/null)"
appops_failed="$(awk '/^===== APPOPS SNAPSHOT =====/{s=1;next}/^===== /&&s{exit}s&&/Failed transaction/{print "yes"; exit}' "$PLAIN" 2>/dev/null)"
sample_awake="$(awk '/^===== POWER \/ WAKELOCK =====/{s=1;next}/^===== /&&s{exit}s&&/mWakefulness=Awake/{print "yes"; exit}' "$PLAIN" 2>/dev/null)"
screen_off_seconds="$(awk '
function dur(tok, n) {
  n=tok
  if (n ~ /ms$/) return 0
  if (n ~ /d$/) { sub(/d$/,"",n); return n*86400 }
  if (n ~ /h$/) { sub(/h$/,"",n); return n*3600 }
  if (n ~ /m$/) { sub(/m$/,"",n); return n*60 }
  if (n ~ /s$/) { sub(/s$/,"",n); return n }
  return 0
}
/Time on battery screen off:/ {
  total=0
  for (i=6; i<=NF; i++) {
    if ($i ~ /^\(/) break
    total += dur($i)
  }
  print int(total)
  exit
}' "$PLAIN" 2>/dev/null)"
screen_off_short=""
if [ -n "$screen_off_seconds" ]; then
  if [ "$screen_off_seconds" -lt 2700 ] 2>/dev/null; then
    screen_off_short="yes"
  fi
fi
no_clean_delta="yes"

{
echo "AIO BATTERY ACTOR ANALYZER v${VERSION}"
echo "Generated: $(date 2>/dev/null)"
echo "Input: $IN"
echo "Output: $OUT"
echo

echo "════════ TÓM TẮT MẪU ════════"
echo "Collector version : ${collector_ver:-unknown}"
echo "Mode              : ${mode:-unknown}"
echo "Generated input   : ${generated:-unknown}"
echo "Device            : ${device:-unknown}"
echo "ROM/SDK           : ${rom:-unknown} / SDK ${sdk:-unknown}"
echo "Battery           : level=${battery_level:-?}% status=${battery_status:-?} temp_raw=${battery_temp_raw:-?} phone_temp_raw=${phone_temp_raw:-?}"
echo "Capacity estimate : ${capacity:-unknown} mAh"
echo "Quality           : ${quality}"
echo "Quality note      : ${quality_note}"
echo
[ -n "$time_on_batt" ] && echo "$time_on_batt"
[ -n "$time_screen_off" ] && echo "$time_screen_off"
[ -n "$screen_on_amount" ] && echo "$screen_on_amount"
[ -n "$screen_off_amount" ] && echo "$screen_off_amount"
[ -n "$actual_drain" ] && echo "$actual_drain"
echo

echo "════════ KẾT LUẬN NHANH ════════"
if [ -n "$top_actor" ]; then
  echo "Top idle suspect  : $top_actor"
  echo "Reason            : $top_reason"
  echo "Score             : $top_score"
else
  echo "Top idle suspect  : none"
  [ -n "$top_reason" ] && echo "Reason            : $top_reason"
fi
echo "Diễn giải          : Điểm là heuristic tổng hợp CPU live, thread CPU, batterystats mAh, wakelock, alarm, job, sensor, location, foreground service, network/sync."
echo "Cảnh báo           : Report này không dùng logcat. App hệ thống như system_server/surfaceflinger/SystemUI có thể là triệu chứng sau khi màn hình thức."
echo

echo "======== QUALITY WARNINGS ========"
[ "$appops_failed" = "yes" ] && echo "- AppOps query failed with transaction errors; permission context is incomplete."
[ "${uidmap_count:-0}" = "0" ] && echo "- UID map is empty; UID-only evidence cannot be mapped to packages."
[ "$sample_awake" = "yes" ] && echo "- Sample was collected while PowerManager reported Awake; live CPU can be post-wake noise."
[ "$screen_off_short" = "yes" ] && echo "- Screen-off duration is under 45 minutes (${screen_off_seconds}s); idle confidence is limited."
[ "$no_clean_delta" = "yes" ] && echo "- No clean before/after delta for UID CPU, network, or kernel wakeup sources; cumulative counters are context only."
echo

echo "======== IDLE SUSPECTS ========"
printf "%-3s %-42s %8s %-24s %8s %8s %8s %8s %6s %6s %6s %6s %6s %6s\n" "#" "Actor" "Score" "Reason" "CPUmax" "CPUavg" "THmax" "mAh" "Job" "Sched" "Wake" "Sens" "Loc" "WL"
awk -F'\t' '$1+0>0{
  printf "%-3d %-42s %8.1f %-24s %8.1f %8.1f %8.1f %8.1f %6d %6d %6d %6d %6d %6d\n", \
    ++n, substr($2,1,42), $1, $3, $4, $5, $6, $7, $9, $10, $11, $12, $13, $14
  if(n>=30) exit
}
END{if(n==0) print "none"}' "$SCORES"
echo

echo "======== POST-WAKE / LIVE CPU SYMPTOMS ========"
printf "%-3s %-42s %8s %-24s %8s %8s %8s %8s\n" "#" "Actor" "Live" "Reason" "CPUmax" "CPUavg" "THmax" "Idle"
awk -F'\t' 'NR<=30{
  printf "%-3d %-42s %8.1f %-24s %8.1f %8.1f %8.1f %8.1f\n", \
    NR, substr($2,1,42), $22, $3, $4, $5, $6, $21
}
END{if(NR==0) print "none"}' "$SYMPTOMS"
echo

echo "======== SYSTEM / AGGREGATE CONTEXT ========"
printf "%-3s %-42s %8s %-24s %8s %8s %8s %8s %6s %6s %6s %6s %6s %6s\n" "#" "Actor" "Live" "Reason" "CPUmax" "CPUavg" "THmax" "mAh" "Job" "Sched" "Wake" "Sens" "Loc" "WL"
awk -F'\t' 'NR<=30{
  printf "%-3d %-42s %8.1f %-24s %8.1f %8.1f %8.1f %8.1f %6d %6d %6d %6d %6d %6d\n", \
    NR, substr($2,1,42), $22, $3, $4, $5, $6, $7, $9, $10, $11, $12, $13, $14
}
END{if(NR==0) print "none"}' "$AGGREGATES"
echo

echo "════════ TOP TÁC NHÂN TỔNG HỢP ════════"
printf "%-3s %-42s %8s %-18s %8s %8s %8s %8s %6s %6s %6s %6s %6s %6s\n" "#" "Actor" "Score" "Reason" "CPUmax" "CPUavg" "THmax" "mAh" "Job" "Sched" "Wake" "Sens" "Loc" "WL"
awk -F'\t' 'NR<=30{
  printf "%-3d %-42s %8.1f %-18s %8.1f %8.1f %8.1f %8.1f %6d %6d %6d %6d %6d %6d\n", \
    NR, substr($2,1,42), $1, $3, $4, $5, $6, $7, $9, $10, $11, $12, $13, $14
}' "$SCORES"
echo

echo "════════ TOP CPU LIVE ════════"
awk -F'\t' '$4+0>0{printf "%-3d %-50s cpu_max=%6.1f cpu_avg=%6.1f score=%6.1f reason=%s\n", ++n, $2, $4, $5, $1, $3; if(n>=15) exit}' "$SCORES"
echo

echo "════════ TOP THREAD CPU ════════"
awk -F'\t' '$6+0>0{printf "%-3d %-50s thread_cpu_max=%6.1f score=%6.1f\n", ++n, $2, $6, $1; if(n>=15) exit}' "$SCORES"
echo

echo "════════ TOP BATTERYSTATS mAh ════════"
awk -F'\t' '$7+0>0{printf "%-3d %-50s mAh=%8.2f score=%6.1f\n", ++n, $2, $7, $1; if(n>=20) exit}' "$SCORES"
echo

echo "════════ TOP WAKELOCK / WAKEUP / SENSOR / LOCATION ════════"
echo "-- Wakelock --"
awk -F'\t' '$14+0>0{printf "%-3d %-50s wakelock_hits=%4d score=%6.1f\n", ++n, $2, $14, $1; if(n>=12) exit}' "$SCORES"
echo "-- Wakeup alarm --"
awk -F'\t' '$11+0>0{printf "%-3d %-50s wakeup_alarm_hits=%4d score=%6.1f\n", ++n, $2, $11, $1; if(n>=12) exit}' "$SCORES"
echo "-- Sensor --"
awk -F'\t' '$12+0>0{printf "%-3d %-50s sensor_hits=%4d score=%6.1f\n", ++n, $2, $12, $1; if(n>=12) exit}' "$SCORES"
echo "-- Location --"
awk -F'\t' '$13+0>0{printf "%-3d %-50s location_hits=%4d score=%6.1f\n", ++n, $2, $13, $1; if(n>=12) exit}' "$SCORES"
echo

echo "════════ TOP JOB / ALARM / FOREGROUND / MEDIA / SYNC / NETWORK ════════"
echo "-- Job/sync scheduler --"
awk -F'\t' '$9+0>0{printf "%-3d %-50s job_hits=%4d score=%6.1f\n", ++n, $2, $9, $1; if(n>=12) exit}' "$SCORES"
echo "-- Scheduled alarm context --"
awk -F'\t' '$10+0>0{printf "%-3d %-50s scheduled_alarm_hits=%4d score=%6.1f\n", ++n, $2, $10, $1; if(n>=12) exit}' "$SCORES"
echo "-- Foreground service --"
awk -F'\t' '$15+0>0{printf "%-3d %-50s fg_hits=%4d score=%6.1f\n", ++n, $2, $15, $1; if(n>=12) exit}' "$SCORES"
echo "-- Media/audio --"
awk -F'\t' '$16+0>0{printf "%-3d %-50s media_hits=%4d score=%6.1f\n", ++n, $2, $16, $1; if(n>=12) exit}' "$SCORES"
echo "-- Media/audio context --"
awk -F'\t' '$25+0>0{printf "%-3d %-50s media_context_hits=%4d score=%6.1f\n", ++n, $2, $25, $1; if(n>=12) exit}' "$SCORES"
echo "-- Sync/account --"
awk -F'\t' '$17+0>0{printf "%-3d %-50s sync_hits=%4d score=%6.1f\n", ++n, $2, $17, $1; if(n>=12) exit}' "$SCORES"
echo "-- Sync/account context --"
awk -F'\t' '$26+0>0{printf "%-3d %-50s sync_context_hits=%4d score=%6.1f\n", ++n, $2, $26, $1; if(n>=12) exit}' "$SCORES"
echo "-- Network --"
awk -F'\t' '$18+0>0{printf "%-3d %-50s network_hits=%4d score=%6.1f\n", ++n, $2, $18, $1; if(n>=12) exit}' "$SCORES"
echo

echo "════════ TRẠNG THÁI LOGD / OTA / MODULE ════════"
awk '
/===== LOGD \/ UPDATE_ENGINE STATE =====/{s=1;print;next}
/^===== /&&s{exit}
s{print}
' "$PLAIN" | head -80
echo

echo "════════ GỢI Ý XỬ LÝ AN TOÀN ════════"
echo "1. Nếu top là app người dùng có CPU cao: force-stop app đó, test idle lại."
echo "2. Nếu top là system_server/surfaceflinger/display composer: xem app màn hình/launcher/SystemUI/WebView/overlay đang kích hoạt chúng."
echo "3. Nếu top do wakeup alarm/job: hạn chế RUN_IN_BACKGROUND/RUN_ANY_IN_BACKGROUND cho app đó, không disable system core ngay."
echo "4. Nếu top do sensor/location: kiểm tra quyền Activity Recognition/Location hoặc tắt gesture/AOD/assistant liên quan."
echo "5. Sau mỗi thay đổi, chạy lại collector --reset-idle rồi --idle để so sánh."
echo

echo "════════ LỆNH KIỂM TRA NHANH TOP SUSPECT ════════"
if [ -n "$top_actor" ]; then
cat <<EOF
su
cmd package path "$top_actor" 2>/dev/null || pm path "$top_actor" 2>/dev/null
cmd appops get "$top_actor" 2>/dev/null
ps -A | grep -F "$top_actor"
dumpsys jobscheduler | grep -F "$top_actor" -A8 -B4
dumpsys alarm | grep -F "$top_actor" -A6 -B4
dumpsys sensorservice | grep -F "$top_actor" -A6 -B4
EOF
fi
echo

echo "════════ DEBUG: EVENT COUNTS ════════"
echo "Events: $(wc -l < "$EVENTS" 2>/dev/null)"
echo "Actors: $(wc -l < "$SCORES" 2>/dev/null)"
echo "UID map entries: ${uidmap_count:-0}"
echo
echo "Report done."
} > "$OUT"

if [ "${KEEP_TMP:-0}" != "1" ]; then
  rm -rf "$TMPDIR" 2>/dev/null
else
  echo "Temp kept: $TMPDIR" >> "$OUT"
fi

aio_log battery SUMMARY done script=battery_actor_analyzer status=ok report="$OUT"
echo "Saved analysis: $OUT"
