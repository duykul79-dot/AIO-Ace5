#!/system/bin/sh
# AIO Ace5 v3.1 - Extreme GT dynamic payload generator
# Sinh payload từ file ROM thật, không sửa trực tiếp file hệ thống, không import devices_config.json.

_SELF="$(readlink -f "$0" 2>/dev/null)"
[ -n "$_SELF" ] || _SELF="$0"
MODDIR="${_SELF%/*}"
MODDIR="${MODDIR%/bin}"
OUT="$MODDIR/bin/extreme_gt_payload_generated"
MANIFEST="$OUT/MANIFEST"
STATS="$OUT/STATS.txt"
SHUTDOWN_FLAG="$MODDIR/bin/thermal_shutdown_disable.flag"
TARGETS_FILE="$MODDIR/bin/game_spoof_targets.conf"
XML_VALIDATE_OK=0
XML_VALIDATE_FAIL=0
XML_SKIPPED_UNSAFE=0

SEARCH_DIRS=""
for d in /odm /my_product /my_stock /vendor /system/vendor /product /system; do
  [ -d "$d" ] && SEARCH_DIRS="$SEARCH_DIRS $d"
done

DENY_CN='com\.tencent|com\.baidu|com\.netease|com\.taobao|com\.alibaba|com\.alicloud|com\.xunmeng|com\.jingdong|com\.jd\.|com\.suning|com\.kuaishou|com\.kwai|com\.ss\.android\.ugc\.aweme|com\.ss\.android\.article|com\.sina|com\.sohu|com\.qiyi|com\.youku|tv\.danmaku\.bili|com\.bilibili|com\.ximalaya|com\.kugou|fm\.qingting|com\.zhihu|com\.xingin|com\.weibo|com\.douban|com\.sankuai|com\.meituan|me\.ele|ctrip\.android|com\.Qunar|com\.huawei|com\.eg\.android\.AlipayGphone|com\.unionpay|cmb\.pb|com\.icbc|hok|Honor of Kings|Vương Giả|wangzhe|sgame|aweme|douyin'

log(){ printf '%s\n' "$*" >> "$STATS" 2>/dev/null; }
perflog(){ printf '[%s] AIO-GEN: %s\n' "$(date +'%H:%M:%S' 2>/dev/null)" "$*" >> /data/local/tmp/aio_performance.log 2>/dev/null; }
add_manifest(){ printf '%s|%s\n' "$1" "$2" >> "$MANIFEST"; }
make_dst(){ mkdir -p "$OUT$(dirname "$1")" 2>/dev/null; printf '%s%s' "$OUT" "$1"; }

find_files(){
  _name="$1"
  for _base in $SEARCH_DIRS; do
    [ -d "$_base" ] || continue
    find "$_base" -type f -name "$_name" 2>/dev/null
  done
}

append_vn_refresh_rules(){
  _file="$1"
  _tmp="$_file.tmp"
  if grep -q '</refresh_rate_config>' "$_file" 2>/dev/null; then
    sed '/<\/refresh_rate_config>/d' "$_file" > "$_tmp"
  else
    cat "$_file" > "$_tmp"
  fi
  printf '\n  <!-- AIO Ace5 game-only FPS rules: only games are forced to max refresh -->\n' >> "$_tmp"
  if [ -f "$TARGETS_FILE" ]; then
    while IFS='|' read -r _pkg _profile _cpu _tweak _label _rest || [ -n "$_pkg" ]; do
      case "$_pkg" in ''|\#*|*[!A-Za-z0-9_.]*|.*|*.|*..*) continue ;; esac
      printf '  <item package="%s" rateId="3-1-2-3" disableViewOverride="true" adfr="true" />\n' "$_pkg" >> "$_tmp"
    done < "$TARGETS_FILE"
  fi
  printf '</refresh_rate_config>\n' >> "$_tmp"
  mv -f "$_tmp" "$_file" 2>/dev/null
}

is_unsafe_minified_xml(){
  _file="$1"
  _lines="$(wc -l < "$_file" 2>/dev/null | tr -d ' ')"
  _lines="${_lines:-999}"
  [ "$_lines" -le 3 ] && grep -q '><' "$_file" 2>/dev/null
}

validate_xml(){
  _file="$1"; _root="$2"
  [ -s "$_file" ] || return 1
  grep -q '<' "$_file" 2>/dev/null || return 1
  grep -q '>' "$_file" 2>/dev/null || return 1
  if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$_file" >/dev/null 2>&1 || return 1; fi
  [ -z "$_root" ] || { grep -q "<$_root" "$_file" 2>/dev/null && grep -q "</$_root>" "$_file" 2>/dev/null; }
}

add_xml_manifest(){
  _group="$1"; _src="$2"; _dst="$3"; _root="$4"
  if validate_xml "$_dst" "$_root"; then
    XML_VALIDATE_OK=$((XML_VALIDATE_OK + 1))
    add_manifest "$_group" "$_src"
    return 0
  fi
  XML_VALIDATE_FAIL=$((XML_VALIDATE_FAIL + 1))
  log "WARN_XML_INVALID_SKIPPED=$_src"
  perflog "WARN XML invalid skipped: $_src"
  rm -f "$_dst" 2>/dev/null
  return 1
}

patch_refresh_rate(){
  _count=0
  _orig_total=0
  _final_total=0
  for src in $(find_files refresh_rate_config.xml); do
    if is_unsafe_minified_xml "$src"; then
      XML_SKIPPED_UNSAFE=$((XML_SKIPPED_UNSAFE + 1))
      log "WARN_XML_MINIFIED_SKIPPED=$src"
      perflog "WARN XML minified skipped: $src"
      continue
    fi
    dst="$(make_dst "$src")"
    orig=$(grep -c '<item ' "$src" 2>/dev/null || printf '0')
    # Game-only mode: keep ROM refresh config for every non-game app.
    # Only remove existing target-game rules to avoid duplicate/lower-FPS entries, then append AIO game max rules.
    cp -fp "$src" "$dst.tmp" 2>/dev/null || continue
    if [ -f "$TARGETS_FILE" ]; then
      while IFS='|' read -r _pkg _profile _cpu _tweak _label _rest || [ -n "$_pkg" ]; do
        case "$_pkg" in ''|\#*|*[!A-Za-z0-9_.]*|.*|*.|*..*) continue ;; esac
        grep -F -v "package=\"$_pkg\"" "$dst.tmp" > "$dst.tmp2" 2>/dev/null && mv -f "$dst.tmp2" "$dst.tmp"
      done < "$TARGETS_FILE"
    fi
    if [ -s "$dst.tmp" ]; then mv -f "$dst.tmp" "$dst"; else cp -fp "$src" "$dst" 2>/dev/null; fi
    append_vn_refresh_rules "$dst"
    final=$(grep -c '<item ' "$dst" 2>/dev/null || printf '0')
    _orig_total=$((_orig_total + orig))
    _final_total=$((_final_total + final))
    add_xml_manifest game "$src" "$dst" refresh_rate_config || continue
    _count=$((_count + 1))
  done
  log "REFRESH_FILES=$_count"
  [ "$_count" -eq 0 ] && log "WARN_REFRESH_CONFIG=missing"
  log "REFRESH_MODE=game_only_stock_apps_untouched"
  log "REFRESH_ORIGINAL_ITEMS=$_orig_total"
  log "REFRESH_FINAL_ITEMS=$_final_total"
}

patch_resolution(){
  # Game-only FPS mode: exclude global display/FPS policy so non-game apps follow ROM stock.
  log "RESOLUTION_FILES=0"
  log "RESOLUTION_MODE=excluded_game_only"
}

patch_thermal_fps(){
  # Game-only FPS mode: exclude global display/FPS policy so non-game apps follow ROM stock.
  log "THERMAL_FPS_FILES=0"
  log "THERMAL_FPS_MODE=excluded_game_only"
}

patch_display_perf(){
  # Game-only FPS mode: exclude global display/FPS policy so non-game apps follow ROM stock.
  log "DISPLAY_PERF_FILES=0"
  log "DISPLAY_PERF_MODE=excluded_game_only"
}

patch_game_thermal(){
  _count=0
  for src in $(find_files game_thermal_config.xml); do
    dst="$(make_dst "$src")"
    if grep -q cluster3 "$src" 2>/dev/null; then
      cat > "$dst" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<game_thermal_config>
    <version>20230829</version>
    <filter-name>game_thermal_config</filter-name>
    <heavy_policy>
        <game_control temp="520" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="60"/>
    </heavy_policy>
    <default_policy>
        <game_control temp="430" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="440" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="450" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="460" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="470" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="480" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="490" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
        <game_control temp="510" cluster0="-1" cluster1="-1" cluster2="-1" cluster3="-1" fps="0"/>
    </default_policy>
</game_thermal_config>
EOF
    else
      cat > "$dst" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<game_thermal_config>
    <version>20230829</version>
    <filter-name>game_thermal_config</filter-name>
    <heavy_policy>
        <game_control temp="520" cluster0="-1" cluster1="-1" cluster2="-1" fps="60"/>
    </heavy_policy>
    <default_policy>
        <game_control temp="430" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="440" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="450" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="460" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="470" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="480" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="490" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
        <game_control temp="510" cluster0="-1" cluster1="-1" cluster2="-1" fps="0"/>
    </default_policy>
</game_thermal_config>
EOF
    fi
    add_xml_manifest game "$src" "$dst" game_thermal_config || continue
    _count=$((_count + 1))
  done
  log "GAME_THERMAL_FILES=$_count"
  [ "$_count" -eq 0 ] && log "WARN_GAME_THERMAL=missing"
}

patch_qega(){
  _count=0
  for src in $(find_files QEGA_Config.txt); do
    dst="$(make_dst "$src")"
    cat > "$dst" <<'EOF'
SkinTemperatureNode:   battery
SkinNodeThrottleTemp:  55000
#GameID   GameAPK    MaxTemperature  MaxCurrent  AvgCurrent
0         adaptive    55000          2000        1800
EOF
    add_manifest game "$src"
    _count=$((_count + 1))
  done
  log "QEGA_FILES=$_count"
}

set_xml_value(){
  _file="$1"; _key="$2"; _value="$3"
  _tmp="$_file.tmp"
  # Safe exact tag replacement. The old greedy pattern could truncate XML when multiple tags were on one line.
  sed "s#<$_key>[^<]*</$_key>#<$_key>$_value</$_key>#g" "$_file" > "$_tmp" 2>/dev/null && mv -f "$_tmp" "$_file"
}

patch_sys_thermal_config(){
  _count=0
  for src in $(find_files sys_thermal_config.xml); do
    if is_unsafe_minified_xml "$src"; then XML_SKIPPED_UNSAFE=$((XML_SKIPPED_UNSAFE + 1)); log "WARN_XML_MINIFIED_SKIPPED=$src"; perflog "WARN XML minified skipped: $src"; continue; fi
    dst="$(make_dst "$src")"
    cp -fp "$src" "$dst" 2>/dev/null || continue
    for kv in isOpen=0 more_heat_threshold=550 heat_threshold=530 less_heat_threshold=500 preheat_threshold=480 preheat_dex_oat_threshold=460 thermal_battery_temp=0 is_feature_on=0 is_upload_log=0 is_upload_errlog=0; do
      key="${kv%%=*}"; val="${kv#*=}"
      set_xml_value "$dst" "$key" "$val"
    done
    # Do not line-drop whole XML here: some ROMs keep multiple tags on one line.
    # CN app filtering is handled in refresh_rate_config; dropping a minified thermal XML line can corrupt boot-critical config.
    add_xml_manifest thermal_policy "$src" "$dst" "" || continue
    _count=$((_count + 1))
  done
  log "SYS_THERMAL_CONFIG_FILES=$_count"
}

patch_thermal_control(){
  _count=0
  for src in $(find_files 'sys_thermal_control_config*.xml'); do
    if is_unsafe_minified_xml "$src"; then XML_SKIPPED_UNSAFE=$((XML_SKIPPED_UNSAFE + 1)); log "WARN_XML_MINIFIED_SKIPPED=$src"; perflog "WARN XML minified skipped: $src"; continue; fi
    dst="$(make_dst "$src")"
    cp -fp "$src" "$dst" 2>/dev/null || continue
    for key in feature_enable_item feature_safety_test_enable_item aging_thermal_control_enable_item; do
      sed "s#<$key[^>]*/>#<$key booleanVal=\"false\" />#g" "$dst" > "$dst.tmp" 2>/dev/null && mv -f "$dst.tmp" "$dst"
    done
    for key in aging_cpu_level_item high_temp_safety_level_item game_high_perf_mode_item normal_mode_item ota_mode_item racing_mode_item; do
      sed "s#<$key[^>]*/>#<$key intVal=\"-1\" />#g" "$dst" > "$dst.tmp" 2>/dev/null && mv -f "$dst.tmp" "$dst"
    done
    add_xml_manifest thermal_policy "$src" "$dst" "" || continue
    _count=$((_count + 1))
  done
  log "THERMAL_CONTROL_FILES=$_count"
}

patch_high_temp(){
  _count=0
  for src in $(find_files 'sys_high_temp_protect*xml'); do
    if is_unsafe_minified_xml "$src"; then XML_SKIPPED_UNSAFE=$((XML_SKIPPED_UNSAFE + 1)); log "WARN_XML_MINIFIED_SKIPPED=$src"; perflog "WARN XML minified skipped: $src"; continue; fi
    dst="$(make_dst "$src")"
    cp -fp "$src" "$dst" 2>/dev/null || continue
    for kv in isOpen=0 HighTemperatureProtectSwitch=false HighTemperatureFirstStepSwitch=false HighTemperatureProtectFirstStepIn=550 HighTemperatureProtectFirstStepOut=530 HighTemperatureProtectThresholdIn=570 HighTemperatureProtectThresholdOut=550 MediumTemperatureProtectThreshold=10000 HighTemperatureDisableFlashSwitch=false HighTemperatureDisableFlashLimit=480 HighTemperatureEnableFlashLimit=470 HighTemperatureDisableFlashChargeSwitch=false HighTemperatureDisableFlashChargeLimit=480 HighTemperatureEnableFlashChargeLimit=470 camera_temperature_limit=520 HighTemperatureControlVideoRecordSwitch=false HighTemperatureDisableVideoRecordLimit=550 HighTemperatureEnableVideoRecordLimit=520 ToleranceThreshold=50 ToleranceStart=480 ToleranceStop=460; do
      key="${kv%%=*}"; val="${kv#*=}"
      set_xml_value "$dst" "$key" "$val"
    done
    if [ -f "$SHUTDOWN_FLAG" ]; then
      set_xml_value "$dst" HighTemperatureShutdownSwitch false
      set_xml_value "$dst" HighTemperatureProtectShutDown 750
      log "SHUTDOWN_PROTECT_PATCH=disabled"
    else
      log "SHUTDOWN_PROTECT_PATCH=stock"
    fi
    add_xml_manifest high_temp "$src" "$dst" "" || continue
    _count=$((_count + 1))
  done
  log "HIGH_TEMP_FILES=$_count"
}

patch_charging(){
  _count=0
  for src in $(find_files 'charging_*txt'); do
    dst="$(make_dst "$src")"
    : > "$dst"
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        *:=*) printf '%s\n' "$line" >> "$dst" ;;
        *,*,*)
          temp="$(printf '%s' "$line" | awk -F, '{print $1}')"
          current="$(printf '%s' "$line" | awk -F, '{print $2}')"
          typ="$(printf '%s' "$line" | awk -F, '{print $3}')"
          case "$temp" in
            ''|*[!0-9-]*) printf '%s\n' "$line" >> "$dst" ;;
            *) printf '%s,%s,%s\n' "$((temp + 50))" "$current" "$typ" >> "$dst" ;;
          esac
        ;;
        *) printf '%s\n' "$line" >> "$dst" ;;
      esac
    done < "$src"
    add_manifest charge "$src"
    _count=$((_count + 1))
  done
  log "CHARGING_FILES=$_count"
  [ "$_count" -eq 0 ] && log "WARN_CHARGING_CONFIG=missing"
  log "CHARGING_TEMP_OFFSET=+5C"
  log "CHARGE_POWER_HINTS=runtime_clear_slow_smart_cooldown_suspend"
}

generate(){
  rm -rf "$OUT" 2>/dev/null
  mkdir -p "$OUT" 2>/dev/null
  : > "$MANIFEST"
  : > "$STATS"
  log "GENERATOR=AIO Ace5 v3.1 charge-plus game-only FPS dynamic Extreme GT 4.2.0 filtered"
  log "DEVICES_CONFIG=excluded"
  log "DIRECT_DATA_SYSTEM_PATCH=excluded"
  log "HORAE_STOP=excluded"
  patch_refresh_rate
  patch_resolution
  patch_thermal_fps
  patch_display_perf
  patch_game_thermal
  patch_qega
  patch_sys_thermal_config
  patch_thermal_control
  patch_high_temp
  patch_charging
  log "XML_VALIDATE_OK=$XML_VALIDATE_OK"
  log "XML_VALIDATE_FAIL=$XML_VALIDATE_FAIL"
  log "XML_SKIPPED_UNSAFE=$XML_SKIPPED_UNSAFE"
  find "$OUT" -type d -exec chmod 0755 {} \; 2>/dev/null
  find "$OUT" -type f -exec chmod 0644 {} \; 2>/dev/null
  printf '[OK] Đã sinh payload Hiệu năng từ ROM hiện tại.\n'
  sed 's/^/INFO_/' "$STATS" 2>/dev/null
}

case "${1:-}" in
  --generate|--force) generate ;;
  --status) [ -f "$STATS" ] && sed 's/^/INFO_/' "$STATS" || printf 'INFO_GENERATOR=not_generated\n' ;;
  --clean) rm -rf "$OUT" 2>/dev/null; printf '[OK] Đã xóa payload generated.\n' ;;
  *) printf '[ERR] aio_extreme_generator.sh: tham so khong hop le: %s\n' "${1:-<none>}"; exit 1 ;;
esac
