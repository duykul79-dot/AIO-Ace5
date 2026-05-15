#!/system/bin/sh
# AIO Ace5 Battery WebUI wrapper.
# Runs the idle collector on demand, analyzes the newest input, and emits a
# compact summary block for webroot/index.html. No boot/background behavior.

set +e

SELF="$(readlink -f "$0" 2>/dev/null)"
[ -n "$SELF" ] || SELF="$0"
BIN_DIR="${SELF%/*}"
COLLECTOR="$BIN_DIR/battery_input_collector_v1_1.sh"
ANALYZER="$BIN_DIR/battery_actor_analyzer_v1_2_2.sh"
QUICK_INPUT="$BIN_DIR/battery_aio_quick_input_v1.sh"
REPORT_DIR="${REPORT_DIR:-/sdcard/Report}"

AIO_LOG_HELPER="$BIN_DIR/aio_log.sh"
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

progress() {
    printf "[PROGRESS] %s|%s\n" "$1" "$2"
}

err() {
    printf "[ERR] %s\n" "$1"
}

warn() {
    printf "[WARN] %s\n" "$1"
}

check_scripts() {
    [ -f "$QUICK_INPUT" ] || { err "Khong tim thay quick input: $QUICK_INPUT"; return 1; }
    [ -f "$ANALYZER" ] || { err "Khong tim thay analyzer: $ANALYZER"; return 1; }
    [ -r "$QUICK_INPUT" ] || { err "Khong doc duoc quick input: $QUICK_INPUT"; return 1; }
    [ -r "$ANALYZER" ] || { err "Khong doc duoc analyzer: $ANALYZER"; return 1; }
    return 0
}

latest_input() {
    _f="$(ls -t "$REPORT_DIR"/battery_input_idle_*.txt 2>/dev/null | head -1)"
    [ -n "$_f" ] && { printf '%s\n' "$_f"; return 0; }
    ls -t "$REPORT_DIR"/battery_input_idle_*.txt.gz 2>/dev/null | head -1
}

latest_report() {
    ls -t "$REPORT_DIR"/battery_analysis_*.txt 2>/dev/null | head -1
}

lookup_app_label() {
    _pkg="$1"
    case "$_pkg" in
        *.*) ;;
        *) printf '%s\n' "$_pkg"; return 0 ;;
    esac
    _tout=""
    if [ -x /system/bin/timeout ]; then
        _tout="/system/bin/timeout"
    elif command -v timeout >/dev/null 2>&1; then
        _tout="$(command -v timeout)"
    fi
    if [ -n "$_tout" ]; then
        _raw="$("$_tout" 3 dumpsys package "$_pkg" 2>/dev/null | head -120)"
    else
        _raw="$(dumpsys package "$_pkg" 2>/dev/null | head -120)"
    fi
    _label="$(printf '%s\n' "$_raw" | awk -F= '
        /nonLocalizedLabel=/ {
            s=$2
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            if (s != "" && s !~ /^0x/) { print s; exit }
        }
        /application-label:/ {
            s=$0
            sub(/^.*application-label:[ \t]*/, "", s)
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            if (s != "") { print s; exit }
        }
        /label=/ {
            s=$2
            gsub(/^[ \t]+|[ \t]+$/, "", s)
            if (s != "" && s !~ /^0x/) { print s; exit }
        }
    ' | head -1)"
    [ -n "$_label" ] || _label="$_pkg"
    printf '%s\n' "$_label"
}

print_list() {
    echo "=== INPUT ==="
    ls -lt "$REPORT_DIR"/battery_input_*.txt "$REPORT_DIR"/battery_input_*.txt.gz 2>/dev/null | head -20
    echo
    echo "=== ANALYSIS ==="
    ls -lt "$REPORT_DIR"/battery_analysis_*.txt 2>/dev/null | head -20
}

emit_summary() {
    _report="$1"
    _input="$2"
    _summary_tmp="${TMPDIR:-/data/local/tmp}/aio_batt_summary_$$.txt"
    awk -v RAW_ANALYSIS="$_report" -v RAW_INPUT="$_input" '
function num(v) { return v + 0 }
function round0(v) { return int(v + 0.5) }
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function parse_time(t, a,n,i,x,sec) {
    sec = 0
    gsub(/,/," ",t)
    n = split(t,a,/ +/)
    for (i=1; i<=n; i++) {
        x = a[i]
        if (x ~ /^[0-9.]+d$/) { sub(/d$/,"",x); sec += x * 86400 }
        else if (x ~ /^[0-9.]+h$/) { sub(/h$/,"",x); sec += x * 3600 }
        else if (x ~ /^[0-9.]+m$/) { sub(/m$/,"",x); sec += x * 60 }
        else if (x ~ /^[0-9.]+s$/) { sub(/s$/,"",x); sec += x }
    }
    return sec
}
function fmt_hm(sec) {
    if (sec < 0) sec = 0
    return int(sec/3600) ":" sprintf("%02d", int((sec%3600)/60))
}
function fmt_num(v, d) {
    if (v == "" || v < 0) return "N/A"
    return sprintf("%." d "f", v)
}
function fmt_vn_ago(sec,    h,m) {
    if (sec <= 0) return "--"
    if (sec < 60) return "vừa xong"
    h = int(sec / 3600)
    m = int((sec % 3600) / 60)
    if (h == 0) return m " phút trước"
    return h " giờ " sprintf("%02d", m) " phút trước"
}
function cap_value(v) {
    v = num(v)
    if (v > 100000) v = v / 1000
    return v
}
function volt_value(v) {
    v = num(v)
    if (v >= 100000) v = v / 1000
    return v
}
function curr_value(v) {
    v = num(v)
    if (v < 0) v = -v
    if (v >= 100000) v = v / 1000
    return v
}
function temp_value(v) {
    v = num(v)
    if (v > 100) v = v / 10
    return v
}
function soh_value(v) {
    v = num(v)
    if (v > 100 && v <= 1000) v = v / 10
    if (v <= 0 || v > 100) return ""
    return v
}
function read_realtime(line, t) {
    t = line
    sub(/^.*: /, "", t)
    sub(/ realtime.*$/, "", t)
    return parse_time(t)
}
function read_uptime(line, t) {
    t = line
    sub(/^.*, /, "", t)
    sub(/ uptime.*$/, "", t)
    return parse_time(t)
}
function add_power_uid(uid, mah, details,    i,j) {
    if (uid == "" || mah <= 0) return
    power_rows_seen++
    if (powern < 20) {
        powern++
        i = powern
    } else if (mah <= power_mah[powern]) {
        return
    } else {
        i = powern
    }
    while (i > 1 && mah > power_mah[i-1]) {
        power_uid[i] = power_uid[i-1]
        power_mah[i] = power_mah[i-1]
        power_details[i] = power_details[i-1]
        i--
    }
    power_uid[i] = uid
    power_mah[i] = mah
    power_details[i] = details
}
function detail_value(d, key,    s) {
    s = d
    if (s !~ ("(^|[ \t])" key ":[ \t]*[0-9.]+")) return ""
    sub("^.*(^|[ \t])" key ":[ \t]*", "", s)
    sub("[^0-9.].*$", "", s)
    return s
}
function detail_summary(d,    out,v) {
    out = ""
    v = detail_value(d, "fg"); if (v != "") out = out "fg " v
    v = detail_value(d, "bg"); if (v != "") out = out (out ? ", " : "") "bg " v
    v = detail_value(d, "cpu"); if (v != "") out = out (out ? ", " : "") "cpu " v
    v = detail_value(d, "wakelock"); if (v != "") out = out (out ? ", " : "") "wakelock " v
    v = detail_value(d, "wifi"); if (v != "") out = out (out ? ", " : "") "wifi " v
    v = detail_value(d, "sensors"); if (v != "") out = out (out ? ", " : "") "sensor " v
    return out != "" ? out : "UID power"
}
FNR==NR {
    if ($0 ~ /^Battery[ \t]*:/) {
        if (match($0, /level=[0-9]+%/)) { s=substr($0,RSTART,RLENGTH); sub(/level=/,"",s); sub(/%/,"",s); level=s+0 }
        if (match($0, /status=[0-9]+/)) { s=substr($0,RSTART,RLENGTH); sub(/status=/,"",s); status=s+0 }
        if (match($0, /temp_raw=[0-9]+/)) { s=substr($0,RSTART,RLENGTH); sub(/temp_raw=/,"",s); temp_dumpsys=s+0 }
    }
    if ($0 ~ /^Capacity estimate[ \t]*:/) {
        s=$0; sub(/^.*:[ \t]*/,"",s); sub(/ .*/,"",s); capacity=num(s)
    }
    if ($0 ~ /^Time on battery:/) {
        elapsed = read_realtime($0)
        uptime = read_uptime($0)
    }
    if ($0 ~ /^Time on battery screen off:/) {
        screenoff = read_realtime($0)
        screenoff_uptime = read_uptime($0)
    }
    if ($0 ~ /^Amount discharged while screen on:/) {
        s=$0; sub(/^.*:[ \t]*/,"",s); screen_on_pct=num(s)
    }
    if ($0 ~ /^Amount discharged while screen off:/) {
        s=$0; sub(/^.*:[ \t]*/,"",s); screen_off_pct=num(s)
    }
    if ($0 ~ /^Capacity:/) {
        s=$0
        if (match(s, /Capacity: *[0-9.]+/)) { c=substr(s,RSTART,RLENGTH); sub(/Capacity: */,"",c); capacity=num(c) }
        if (match(s, /Computed drain: *[0-9.]+/)) { c=substr(s,RSTART,RLENGTH); sub(/Computed drain: */,"",c); computed=num(c) }
    }
    if ($0 ~ /^[ \t]*Discharge:[ \t]*[0-9.]+[ \t]*mAh/) {
        s=$0; sub(/^.*Discharge:[ \t]*/,"",s); sub(/[^0-9.].*$/,"",s)
        if (s ~ /^[0-9]+(\.[0-9]+)?$/) discharge_mah=s+0
    }
    if ($0 ~ /(^|[^0-9.])[0-9]+(\.[0-9]+)?%/ && ($0 ~ /Pin/ || $0 ~ /Used|used|USED/)) {
        s=$0; sub(/%.*$/,"",s); sub(/^.*[^0-9.]/,"",s)
        if (s ~ /^[0-9]+(\.[0-9]+)?$/) used_pct_input=s+0
    }
    if ($0 ~ /Sample was collected while .*Awake/) awake_warn=1
    if ($0 ~ /Screen-off duration is under 45 minutes/) short_warn=1
    if ($0 ~ /^Top idle suspect[ \t]*:/) { top_suspect=$0; sub(/^.*:[ \t]*/,"",top_suspect) }

    if ($0 ~ /^======== IDLE SUSPECTS ========/) { in_idle=1; next }
    if (in_idle && $0 ~ /^======== /) { in_idle=0 }
    if (in_idle && $1 ~ /^[0-9]+$/ && topn < 20) {
        actor=$2
        if (actor ~ /^(android|android\/system|android\/system_context|uid\/1000|radio\/system|system_server|surfaceflinger|com\.android\.systemui|com\.android\.launcher|collector_.*)$/) next
        if (actor ~ /^android\.hardware\./ || actor ~ /^vendor\.qti\.hardware\.display\./) next
        if (actor ~ /^(crtc_commit|kgsl_hwsched|gmu_f2h)$/) next
        score=0; mah=-1; nth=0
        for (i=3; i<=NF; i++) {
            if ($i ~ /^-?[0-9]+(\.[0-9]+)?$/) {
                nth++
                if (nth == 1) score=$i+0
                if (nth == 5) mah=$i+0
            }
        }
        if (score > 0) {
            topn++
            top_actor[topn]=actor
            top_score[topn]=score
            top_mah[topn]=mah
            total_score += score
        }
    }
    next
}
{
    low=tolower($0)
    if (elapsed <= 0 && low ~ /^[ \t]*time on battery:/) {
        elapsed = read_realtime($0)
        uptime = read_uptime($0)
    }
    if (screenoff <= 0 && low ~ /^[ \t]*time on battery screen off:/) {
        screenoff = read_realtime($0)
        screenoff_uptime = read_uptime($0)
    }
    if (low ~ /^[ \t]*discharge:[ \t]*[0-9.]+[ \t]*mah/) {
        s=low; sub(/^.*discharge:[ \t]*/,"",s); sub(/[^0-9.].*$/,"",s)
        if (s ~ /^[0-9]+(\.[0-9]+)?$/) discharge_mah=s+0
    }
    if ($0 ~ /(^|[^0-9.])[0-9]+(\.[0-9]+)?%/ && ($0 ~ /Pin/ || low ~ /(^|[^a-z])(used|used_pct|pin da su dung|pin đã sử dụng)/)) {
        s=$0; sub(/%.*$/,"",s); sub(/^.*[^0-9.]/,"",s)
        if (s ~ /^[0-9]+(\.[0-9]+)?$/) used_pct_input=s+0
    }
    if (temp_dumpsys == "" && low ~ /^[ \t]*temperature[ \t]*:[ \t]*-?[0-9]+/) {
        s=low
        sub(/^.*temperature[ \t]*:[ \t]*/,"",s)
        sub(/[^0-9-].*$/,"",s)
        if (s ~ /^-?[0-9]+$/) temp_dumpsys=s+0
    }
    if (temp_phone == "" && low ~ /phonetemp[ \t]*:[ \t]*-?[0-9]+/) {
        s=low
        sub(/^.*phonetemp[ \t]*:[ \t]*/,"",s)
        sub(/[^0-9-].*$/,"",s)
        if (s ~ /^-?[0-9]+$/) temp_phone=s+0
    }
    if (low ~ /^[ \t]*estimated power use \(mah\):/) {
        in_power = 1
        next
    }
    if (in_power && $0 ~ /^[ \t]*UID[ \t]+[^:]+:[ \t]*[0-9.]+/) {
        s=$0
        uid=s
        sub(/^[ \t]*UID[ \t]+/,"",uid)
        sub(/:.*/,"",uid)
        uid=trim(uid)
        mah=s
        sub(/^[ \t]*UID[ \t]+[^:]+:[ \t]*/,"",mah)
        sub(/[ \t].*$/,"",mah)
        details=s
        sub(/^[ \t]*UID[ \t]+[^:]+:[ \t]*[0-9.]+[ \t]*/,"",details)
        if (mah ~ /^[0-9]+(\.[0-9]+)?$/) add_power_uid(uid, mah+0, details)
        next
    }
    if (low ~ /^[a-z0-9_]+=/) {
        k=low
        sub(/=.*/,"",k)
        v=$0
        sub(/^[^=]+=/,"",v)
        sub(/[ \t\r].*$/,"",v)
        if (k == "battery_soh" || k == "battery_battery_soh" || k == "soh") {
            if (soh_pct == "" && v ~ /^[0-9]+(\.[0-9]+)?$/) {
                soh_pct=soh_value(v)
                soh_source="SOH"
            }
        } else if (k == "battery_health" || k == "raw_battery_health" || k == "raw_soh") {
            if (soh_pct == "" && v ~ /^[0-9]+(\.[0-9]+)?$/) {
                soh_pct=soh_value(v)
                soh_source="RAW_SOH"
            }
        } else if ((k == "charge_full_design" || k == "battery_charge_full_design" || k == "bms_charge_full_design") && design_capacity == "") {
            if (v ~ /^[0-9]+$/) design_capacity=cap_value(v)
        } else if ((k == "battery_fcc" || k == "battery_battery_fcc" || k == "batt_cc" || k == "battery_batt_cc") && battery_fcc == "") {
            if (v ~ /^[0-9]+$/) battery_fcc=cap_value(v)
        } else if ((k == "bms_charge_full") && bms_charge_full == "") {
            if (v ~ /^[0-9]+$/) bms_charge_full=cap_value(v)
        } else if ((k == "battery_charge_full") && battery_charge_full == "") {
            if (v ~ /^[0-9]+$/) battery_charge_full=cap_value(v)
        } else if (k == "charge_full" && charge_full == "") {
            if (v ~ /^[0-9]+$/) charge_full=cap_value(v)
        } else if ((k == "voltage" || k == "voltage_now" || k == "battery_voltage_now" || k == "bms_voltage_now") && voltage_mv == "") {
            if (v ~ /^-?[0-9]+$/) voltage_mv=volt_value(v)
        } else if ((k == "current" || k == "current_now" || k == "battery_current_now" || k == "bms_current_now") && current_ma == "") {
            if (v ~ /^-?[0-9]+$/) current_ma=curr_value(v)
        } else if ((k == "battery_temp" || k == "temp") && temp_sysfs == "") {
            if (v ~ /^-?[0-9]+$/) temp_sysfs=v+0
        }
    }
    if (low ~ /cycle_count=/ && cycle_count == "") {
        s=$0; sub(/^.*cycle_count=/,"",s); sub(/[ \t\r].*$/,"",s)
        if (s ~ /^[0-9]+$/) cycle_count=s
    }
    if (low ~ /charge_full_design=/ && design_capacity == "") {
        s=$0; sub(/^.*charge_full_design=/,"",s); sub(/[ \t\r].*$/,"",s)
        if (s ~ /^[0-9]+$/) design_capacity=cap_value(s)
    }
    if (low ~ /battery_fcc=/ && battery_fcc == "") {
        s=$0; sub(/^.*battery_fcc=/,"",s); sub(/[ \t\r].*$/,"",s)
        if (s ~ /^[0-9]+$/) battery_fcc=cap_value(s)
    }
    if (low ~ /bms_charge_full=/ && bms_charge_full == "") {
        s=$0; sub(/^.*bms_charge_full=/,"",s); sub(/[ \t\r].*$/,"",s)
        if (s ~ /^[0-9]+$/) bms_charge_full=cap_value(s)
    }
    if (low ~ /battery_charge_full=/ && battery_charge_full == "") {
        s=$0; sub(/^.*battery_charge_full=/,"",s); sub(/[ \t\r].*$/,"",s)
        if (s ~ /^[0-9]+$/) battery_charge_full=cap_value(s)
    }
    if (low ~ /charge_full=/ && charge_full == "" && low !~ /charge_full_design=/) {
        s=$0; sub(/^.*charge_full=/,"",s); sub(/[ \t\r].*$/,"",s)
        if (s ~ /^[0-9]+$/) charge_full=cap_value(s)
    }
    if (soh_pct == "" && low ~ /(^|[^a-z])(soh|battery_soh|state_of_health|health_pct)[=:][0-9.]+/) {
        s=low
        sub(/^.*(soh|state_of_health|battery_soh|health_pct)[=:]/,"",s)
        sub(/[^0-9.].*$/,"",s)
        if (s ~ /^[0-9]+(\.[0-9]+)?$/) {
            soh_pct=soh_value(s)
            soh_source="SOH"
        }
    }
    if (design_capacity == "" && low ~ /(estimated battery capacity|last learned battery capacity|min learned battery capacity|max learned battery capacity)[ \t]*:/) {
        s=low
        sub(/^.*:[ \t]*/,"",s)
        sub(/[^0-9.].*$/,"",s)
        if (s ~ /^[0-9]+(\.[0-9]+)?$/) design_capacity=cap_value(s)
    }
    if (voltage_mv == "" && low ~ /^[ \t]*voltage[ \t]*:/) {
        s=low
        sub(/^.*voltage[ \t]*:[ \t]*/,"",s)
        sub(/[^0-9-].*$/,"",s)
        if (s ~ /^-?[0-9]+$/) voltage_mv=volt_value(s)
    }
    if (current_ma == "" && low ~ /battery current[ \t]*:/) {
        s=low
        sub(/^.*battery current[ \t]*:[ \t]*/,"",s)
        sub(/[^0-9-].*$/,"",s)
        if (s ~ /^-?[0-9]+$/) current_ma=curr_value(s)
    }
}
END {
    if (capacity <= 0 && charge_full > 0) capacity=charge_full
    if (computed > 0) {
        used_mah=computed
        used_estimated=0
    } else if (discharge_mah > 0) {
        used_mah=discharge_mah
        used_estimated=0
    } else {
        if (capacity > 0) used_mah=capacity * (screen_on_pct + screen_off_pct) / 100
        else used_mah=0
        used_estimated=1
    }
    used_pct = used_pct_input > 0 ? used_pct_input : (capacity > 0 ? used_mah / capacity * 100 : 0)
    unplug_pct = level + used_pct
    if (unplug_pct > 100) unplug_pct=100
    unplug_mah = capacity > 0 ? capacity * unplug_pct / 100 : 0
    onscreen = elapsed - screenoff
    deepsleep = screenoff - screenoff_uptime
    if (screen_off_pct > 0 && capacity > 0) {
        deepsleep_pct=screen_off_pct
        deepsleep_mah=capacity * deepsleep_pct / 100
    } else if (elapsed > 0 && used_mah > 0) {
        deepsleep_mah=used_mah * screenoff / elapsed
        deepsleep_pct=capacity > 0 ? deepsleep_mah / capacity * 100 : 0
    }
    if (used_mah > 0 && deepsleep_mah > used_mah) {
        deepsleep_mah = used_mah
        deepsleep_pct = used_pct
    }
    if (used_pct > 0 && deepsleep_pct > used_pct) {
        deepsleep_pct = used_pct
        deepsleep_mah = used_mah
    }
    if (used_mah <= 0) {
        deepsleep_mah = 0
        deepsleep_pct = 0
    }
    temp_c = temp_dumpsys != "" ? temp_value(temp_dumpsys) : (temp_sysfs != "" ? temp_value(temp_sysfs) : (temp_phone != "" ? temp_value(temp_phone) : -1))
    # Real full-charge capacity after wear. Do not fall back to design/nominal capacity.
    real_capacity = 0
    health = -1
    real_source = "N/A"
    if (design_capacity > 0 && soh_pct != "" && soh_pct > 0) {
        real_capacity = design_capacity * soh_pct / 100
        health = soh_pct
        real_source = (soh_source != "" ? soh_source : "SOH")
    } else if (battery_fcc > 0 && design_capacity > 0) {
        real_capacity = battery_fcc
        health = real_capacity / design_capacity * 100
        real_source = "FCC_FALLBACK"
    } else if (bms_charge_full > 0 && design_capacity > 0 && int(bms_charge_full + 0.5) != int(design_capacity + 0.5)) {
        real_capacity = bms_charge_full
        health = real_capacity / design_capacity * 100
        real_source = "CHARGE_FULL_FALLBACK"
    } else if (battery_charge_full > 0 && design_capacity > 0 && int(battery_charge_full + 0.5) != int(design_capacity + 0.5)) {
        real_capacity = battery_charge_full
        health = real_capacity / design_capacity * 100
        real_source = "CHARGE_FULL_FALLBACK"
    } else if (charge_full > 0 && design_capacity > 0 && int(charge_full + 0.5) != int(design_capacity + 0.5)) {
        real_capacity = charge_full
        health = real_capacity / design_capacity * 100
        real_source = "CHARGE_FULL_FALLBACK"
    }
    if (real_capacity > 0) {
        if (health >= 0) real_cap_text = round0(real_capacity) " mAh (" fmt_num(health, 1) "%)"
        else real_cap_text = round0(real_capacity) " mAh (N/A)"
    } else {
        real_cap_text = "N/A"
    }
    if (elapsed > 0) {
        if (used_pct_input > 0) avg_drain = used_pct_input / (elapsed / 3600)
        else if (used_mah > 0 && real_capacity > 0) avg_drain = used_mah / real_capacity * 100 / (elapsed / 3600)
        else avg_drain = used_pct / (elapsed / 3600)
    } else {
        avg_drain = 0
    }
    battery_power_w = -1
    if (voltage_mv > 0 && current_ma > 0) battery_power_w = voltage_mv * current_ma / 1000000

    if (status == 2 || status == 5) print "[WARN] May dang sac. Ket qua khong phu hop de do pin cho."
    if (awake_warn) print "[WARN] Mau duoc thu khi may dang Awake; CPU live co the la nhieu sau khi mo man hinh."
    if (short_warn || (screenoff > 0 && screenoff < 2700)) print "[WARN] Thoi gian screen-off duoi 45 phut, do tin cay han che."
    if (elapsed > 0 && elapsed < 600) print "[WARN] Mau ngan, toc do xa chi mang tinh tham khao."

    print "=== AIO_BATTERY_SUMMARY_BEGIN ==="
    print "UNPLUG_ELAPSED=" fmt_hm(elapsed)
    print "UNPLUG_AGO_TEXT=" fmt_vn_ago(elapsed)
    print "UNPLUG_MAH=" round0(used_mah)
    print "UNPLUG_PCT=" fmt_num(used_pct, 2)
    print "UNPLUG_BATTERY_MAH=" round0(unplug_mah)
    print "UNPLUG_BATTERY_PCT=" round0(unplug_pct)
    print "USED_ESTIMATED=" used_estimated
    print "USED_MAH=" (used_estimated ? "~" : "") round0(used_mah)
    print "USED_PCT=" (used_estimated ? "~" : "") fmt_num(used_pct, 2)
    print "ONSCREEN=" fmt_hm(onscreen)
    print "DEEPSLEEP=" fmt_hm(deepsleep)
    print "DEEPSLEEP_MAH=" round0(deepsleep_mah)
    print "DEEPSLEEP_PCT=" fmt_num(deepsleep_pct, 2)
    print "AVG_DRAIN_PCT_H=" fmt_num(avg_drain, 2)
    print "TEMP_C=" (temp_c >= 0 ? fmt_num(temp_c, 1) : "N/A")
    print "CYCLE_COUNT=" (cycle_count != "" ? cycle_count : "N/A")
    print "REAL_CAPACITY_MAH=" (real_capacity > 0 ? round0(real_capacity) : "N/A")
    print "REAL_CAPACITY_PCT=" (health >= 0 ? fmt_num(health, 1) : "N/A")
    print "REAL_CAPACITY_TEXT=" real_cap_text
    print "REAL_CAPACITY_SOURCE=" real_source
    print "REAL_CAPACITY_DESIGN_MAH=" (design_capacity > 0 ? round0(design_capacity) : "N/A")
    print "REAL_CAPACITY_SOH=" (soh_pct != "" ? fmt_num(soh_pct, 1) : "N/A")
    print "REAL_CAPACITY_FCC_MAH=" (battery_fcc > 0 ? round0(battery_fcc) : "N/A")
    print "BATTERY_VOLTAGE_MV=" (voltage_mv > 0 ? round0(voltage_mv) : "N/A")
    print "BATTERY_CURRENT_MA=" (current_ma > 0 ? round0(current_ma) : "N/A")
    print "BATTERY_POWER_W=" (battery_power_w >= 0 ? fmt_num(battery_power_w, 2) : "N/A")
    print "BATTERY_POWER_TEXT=" (battery_power_w >= 0 ? fmt_num(battery_power_w, 2) " W" : "--")
    print "TOP_SUSPECT=" (top_suspect != "" ? top_suspect : "none")
    if (topn <= 0 && powern > 0) {
        for (i=1; i<=powern; i++) {
            topn++
            top_actor[topn]=power_uid[i]
            top_score[topn]=power_mah[i]
            top_mah[topn]=power_mah[i]
            top_detail[topn]=detail_summary(power_details[i])
            total_score += power_mah[i]
        }
        top_source = "UID_POWER_FALLBACK"
    } else {
        top_source = (topn > 0 ? "ANALYZER_IDLE" : "EMPTY")
    }
    print "TOP_SOURCE=" top_source
    print "TOP_UID_ROWS=" power_rows_seen+0
    print "TOP_BEGIN"
    for (i=1; i<=topn; i++) {
        if (total_score > 0) {
            dur = (top_detail[i] != "" ? top_detail[i] : "~" fmt_hm(uptime * top_score[i] / total_score))
            if (top_mah[i] > 0) {
                mah = fmt_num(top_mah[i], 1)
                pct = used_mah > 0 ? fmt_num(top_mah[i] / used_mah * 100, 1) : "--"
            } else {
                mahv = used_mah * top_score[i] / total_score
                mah = "~" fmt_num(mahv, 1)
                pct = used_mah > 0 ? "~" fmt_num(mahv / used_mah * 100, 1) : "--"
            }
            print i "|" top_actor[i] "|" dur "|" mah "|" pct
        } else {
            print i "|" top_actor[i] "|--:--|--|--"
        }
    }
    print "TOP_END"
    print "RAW_ANALYSIS=" RAW_ANALYSIS
    print "RAW_INPUT=" RAW_INPUT
    print "=== AIO_BATTERY_SUMMARY_END ==="
}
' "$_report" "$_input" > "$_summary_tmp"
    while IFS= read -r _line; do
        if [ "$_line" = "=== AIO_BATTERY_SUMMARY_END ===" ]; then
            awk '
                $0=="TOP_BEGIN" { in_top=1; next }
                $0=="TOP_END" { in_top=0; next }
                in_top && $0 ~ /^[0-9]+\|/ {
                    n=split($0,p,"|")
                    if (n >= 2 && !seen[p[2]]++) print p[2]
                }
            ' "$_summary_tmp" | while IFS= read -r _pkg; do
                [ -n "$_pkg" ] || continue
                _label="$(lookup_app_label "$_pkg")"
                printf 'LABEL|%s|%s\n' "$_pkg" "$_label"
            done
        fi
        printf '%s\n' "$_line"
    done < "$_summary_tmp"
    rm -f "$_summary_tmp" 2>/dev/null
}

run_all() {
    aio_log battery INFO START script=battery_aio_report mode=run
    progress 5 "Chuan bi phan tich pin"
    check_scripts || { aio_log battery ERR failed script=battery_aio_report status=error step=check_scripts; return 1; }
    mkdir -p "$REPORT_DIR" 2>/dev/null

    progress 20 "Thu input pin nhanh"
    REPORT_DIR="$REPORT_DIR" /system/bin/sh "$QUICK_INPUT"
    _rc=$?
    [ "$_rc" -eq 0 ] || { err "Khong tao duoc input pin."; aio_log battery ERR failed script=battery_aio_report status=error step=quick_input rc=$_rc; return "$_rc"; }

    _input="$(latest_input)"
    [ -n "$_input" ] || { err "Khong tim thay battery_input_idle_*.txt"; aio_log battery ERR failed script=battery_aio_report status=error step=latest_input; return 1; }
    progress 35 "Da thu input"
    printf "[OK] Da luu input pin nhanh\n"

    progress 45 "Chay analyzer"
    REPORT_DIR="$REPORT_DIR" /system/bin/sh "$ANALYZER" "$_input"
    _rc=$?
    [ "$_rc" -eq 0 ] || { err "Analyzer khong tao duoc report."; aio_log battery ERR failed script=battery_aio_report status=error step=analyzer rc=$_rc; return "$_rc"; }

    _report="$(latest_report)"
    [ -n "$_report" ] || { err "Analyzer khong tao duoc report."; aio_log battery ERR failed script=battery_aio_report status=error step=latest_report; return 1; }
    progress 70 "Dung bang report"
    printf "[OK] Bao cao da luu\n"

    if [ -s "$_report" ]; then
        _summary_input="$_input"
        _tmp_summary=""
        case "$_input" in
            *.gz)
                _tmp_summary="/data/local/tmp/aio_batt_input_$$.txt"
                if command -v gzip >/dev/null 2>&1; then
                    gzip -dc "$_input" > "$_tmp_summary" 2>/dev/null
                elif command -v busybox >/dev/null 2>&1; then
                    busybox gzip -dc "$_input" > "$_tmp_summary" 2>/dev/null
                fi
                [ -s "$_tmp_summary" ] && _summary_input="$_tmp_summary"
                ;;
        esac
        emit_summary "$_report" "$_summary_input"
        [ -n "$_tmp_summary" ] && rm -f "$_tmp_summary" 2>/dev/null
    else
        warn "Khong parse duoc summary, hien thi raw report."
    fi

    progress 100 "Hoan tat"
    aio_log battery SUMMARY done script=battery_aio_report status=ok
    printf "[OK] Hoan tat\n"
}

case "${1:-}" in
    --run|"")
        run_all
        ;;
    --show-latest)
        _report="$(latest_report)"
        [ -n "$_report" ] || { err "Khong tim thay battery_analysis_*.txt"; exit 1; }
        printf "[OK] Bao cao da luu\n"
        ;;
    --list)
        print_list
        ;;
    --help|-h)
        echo "Usage:"
        echo "  sh battery_aio_report_v1.sh --run"
        echo "  sh battery_aio_report_v1.sh --show-latest"
        echo "  sh battery_aio_report_v1.sh --list"
        ;;
    *)
        err "Tham so khong hop le: $1"
        exit 1
        ;;
esac
