#!/system/bin/sh
# AIO Ace5 Game Spoof config manager
# Live mode: exports COPG-compatible config and runs bundled COPG Zygisk engine via a path shim.
# It does NOT resetprop global props; spoof is per-app through Zygisk when enabled.

MODDIR=${0%/*}/..
MODDIR=$(cd "$MODDIR" 2>/dev/null && pwd || echo "/data/adb/modules/cleanup_ace5_v10_5")
BIN_DIR="$MODDIR/bin"
OLD_FLAG="$BIN_DIR/game_spoof_enabled.flag"
STATE_DIR="/data/adb/aio_ace5/state"
FLAG="$STATE_DIR/game_spoof_enabled.flag"
PROFILES_FILE="$BIN_DIR/game_spoof_profiles.conf"
TARGETS_FILE="$BIN_DIR/game_spoof_targets.conf"
CPU_BLACKLIST_FILE="$BIN_DIR/game_spoof_cpu_blacklist.conf"
CPUINFO_FILE="$BIN_DIR/game_spoof_cpuinfo.txt"
JSON_FILE="$BIN_DIR/game_spoof_config.json"
COPG_JSON_FILE="$BIN_DIR/game_spoof_copg_compat.json"
PUBLIC_JSON="/data/local/tmp/aio_game_spoof_config.json"
PUBLIC_COPG_JSON="/data/local/tmp/aio_game_spoof_copg_compat.json"
PUBLIC_CPUINFO="/data/local/tmp/aio_game_spoof_cpuinfo.txt"
LOG_FILE="/data/local/tmp/aio_game_spoof.log"
COPG_COMPAT_DIR="/data/adb/modules/COPG"
COPG_COMPAT_MARKER="$COPG_COMPAT_DIR/.aio_owned"
COPG_COMPAT_SIGNATURE="$COPG_COMPAT_DIR/.aio_signature_v31"
COPG_COMPAT_JSON="$COPG_COMPAT_DIR/COPG.json"
COPG_COMPAT_CPUINFO="$COPG_COMPAT_DIR/cpuinfo_spoof"
COPG_COMPAT_CONTROLLER="$COPG_COMPAT_DIR/controller"
COPG_ENGINE_DIR="$BIN_DIR/copg_engine"
COPG_CONTROLLER_PID="/data/local/tmp/aio_game_spoof_copg_controller.pid"
COPG_ZYGISK_ARM64="$MODDIR/zygisk/arm64-v8a.so"
COPG_ZYGISK_ARMV7="$MODDIR/zygisk/armeabi-v7a.so"

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

_ensure_state_dir(){
    mkdir -p "$STATE_DIR" 2>/dev/null
}

_migrate_state(){
    if [ -f "$OLD_FLAG" ] && [ ! -f "$FLAG" ]; then
        _ensure_state_dir
        : > "$FLAG" 2>/dev/null && chmod 0600 "$FLAG" 2>/dev/null
    fi
}

_spoof_enabled(){
    _migrate_state
    [ -f "$FLAG" ]
}

_log(){
    mkdir -p /data/local/tmp 2>/dev/null
    printf '[%s] AIO-SPOOF: %s\n' "$(date '+%H:%M:%S' 2>/dev/null || echo '00:00:00')" "$*" >> "$LOG_FILE" 2>/dev/null
}

_json_escape(){
    # Values are config-controlled and line-based; keep JSON safe for common characters.
    printf '%s' "$1" | tr '\n\r\t' '   ' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_valid_pkg(){
    case "$1" in
        ''|*[!A-Za-z0-9_.]*) return 1 ;;
        *) return 0 ;;
    esac
}

_valid_id(){
    case "$1" in
        ''|*[!A-Za-z0-9_]* ) return 1 ;;
        *) return 0 ;;
    esac
}

_init_profiles(){
    [ -f "$PROFILES_FILE" ] && return 0
    cat > "$PROFILES_FILE" <<'PROFILES_EOF'
# profile_id|label|BRAND|MANUFACTURER|DEVICE|PRODUCT|MODEL|FINGERPRINT|BOARD|HARDWARE
REDMAGIC_10_PRO|RedMagic 10 Pro|nubia|ZTE|RedMagic 10 Pro|NX789J|NX789J|nubia/NX789J-UN/NX789J:15/AQ3A.240812.002/20241212.194919:user/release-keys||
REALME_15_PRO_5G|Realme 15 Pro 5G|realme|realme|Realme 15 Pro 5G|RMX5101|RMX5101|realme/RMX5101IN/RE60B4L1:15/AP3A.240617.008/V.R4T2.26cec0e-80bb4e-80b757:user/release-keys||
REALME_16_PRO_PLUS|Realme 16 Pro+ 5G|realme|realme|RE6458L1|RMX5131IN|Realme 16 Pro+ 5G|||
REALME_P3_5G|Realme P3 5G|realme|realme|Realme P3 5G|RMX5070|RMX5070|realme/RMX5070/RMX5070:15/SKQ1.230119.001/eng.user.20250415.155201:user/release-keys||
XIAOMI_13_PRO|Xiaomi 13 Pro|Xiaomi|Xiaomi|Xiaomi 13 Pro|2210132G|2210132G|Xiaomi/fuxi_eea/fuxi:13/TKQ1.221114.001/OS2.0.102.0.VMCEUXM:user/release-keys||
ONEPLUS_8_PRO_5G|OnePlus 8 Pro 5G|OnePlus|OnePlus|OnePlus 8 Pro 5G|IN2023|IN2023|OnePlus/IN2023/OnePlus8Pro:13/RKQ1.211119.001/20230501:user/release-keys||
REDMAGIC_9_PRO|RedMagic 9 Pro|nubia|ZTE|REDMAGIC 9 Pro|NX769J|NX769J|nubia/NX769J/NX769J:14/UKQ1.230917.001/20240813.173312:user/release-keys||
XIAOMI_11T_PRO|Xiaomi 11T Pro|Xiaomi|Xiaomi|Xiaomi 11T Pro|2107113SG|2107113SG|Xiaomi/2107113SI/Mi 11T Pro:13/RKQ1.211001.001/20230410:user/release-keys||
LEGION_Y700_2023|Legion Y700 2023|Lenovo|Lenovo|Legion Y700 (2023)|TB-9707F|TB-9707F|Lenovo/TB-9707F/Lenovo TB-9707F:13/TQ3A.230805.001/20230901:user/release-keys||
ROG_PHONE_6D_ULTIMATE|ROG Phone 6D Ultimate|ASUS|ASUS|ROG Phone 6D Ultimate|AI2203|AI2203|ASUS/AI2203/ROG Phone 6D:14/UP1A.231005.007/20240315:user/release-keys||
GALAXY_Z_FOLD_5|Galaxy Z Fold 5|samsung|samsung|Galaxy Z Fold 5|SM-F9460|SM-F9460|samsung/q2qzh/q2q:15/UP1A.231005.007/F946BXXU1BWK4:user/release-keys||
ONEPLUS_13|OnePlus 13|OnePlus|OnePlus|OnePlus 13|PJZ110|PJZ110|OnePlus/PJZ110/OP5D0DL1:15/AP3A.240617.008/V.1bd19a1-1-2:user/release-keys||
HONOR_MAGIC_V2_RSR|Honor Magic V2 RSR|HONOR|HONOR|Honor Magic V2 RSR|VER-AN10|VER-AN10|HONOR/VER-AN10/HNVER:14/HONORVER-AN10/8.0.0.110:user/release-keys||
PROFILES_EOF
    chmod 0600 "$PROFILES_FILE" 2>/dev/null
}

_init_targets(){
    [ -f "$TARGETS_FILE" ] && return 0
    cat > "$TARGETS_FILE" <<'TARGETS_EOF'
# package|profile_id|cpu_mode|tweak_mode|label
com.garena.game.kgvn|REALME_15_PRO_5G|blocked|normal|Liên Quân Mobile VN
com.vng.codmvn|REDMAGIC_10_PRO|blocked|normal|Call of Duty Mobile VN
com.garena.game.codm|REDMAGIC_10_PRO|blocked|normal|Call of Duty Mobile Garena
com.activision.callofduty.shooter|REDMAGIC_10_PRO|blocked|normal|Call of Duty Mobile Global
com.vng.pubgmobile|XIAOMI_13_PRO|blocked|normal|PUBG Mobile VN
com.pubg.krmobile|XIAOMI_13_PRO|blocked|normal|PUBG Mobile Korea
com.pubg.imobile|XIAOMI_13_PRO|blocked|normal|PUBG Mobile India
com.dts.freefireth|REALME_P3_5G|blocked|normal|Free Fire
com.dts.freefiremax|REALME_P3_5G|blocked|normal|Free Fire MAX
com.riotgames.league.wildriftvn|ONEPLUS_8_PRO_5G|blocked|normal|Wild Rift VN
com.riotgames.league.wildrift|ONEPLUS_8_PRO_5G|blocked|normal|Wild Rift Global
com.mobile.legends|REDMAGIC_9_PRO|blocked|normal|Mobile Legends
com.vng.mlbbvn|XIAOMI_11T_PRO|blocked|normal|Mobile Legends VN
com.roblox.client|REDMAGIC_9_PRO|blocked|normal|Roblox
com.supercell.brawlstars|REDMAGIC_9_PRO|blocked|normal|Brawl Stars
com.supercell.clashofclans|XIAOMI_11T_PRO|blocked|normal|Clash of Clans
com.supercell.clashroyale|REDMAGIC_9_PRO|blocked|normal|Clash Royale
com.epicgames.fortnite|REDMAGIC_9_PRO|cpu_only|minimal|Fortnite
com.miraclegames.farlight84|REDMAGIC_9_PRO|cpu_only|minimal|Farlight 84
com.ea.gp.fifamobile|GALAXY_Z_FOLD_5|blocked|normal|EA Sports FC Mobile
jp.konami.pesam|REDMAGIC_9_PRO|blocked|normal|eFootball
com.kurogame.wutheringwaves.global|REDMAGIC_10_PRO|blocked|normal|Wuthering Waves Global
com.levelinfinite.hotta.gp|XIAOMI_11T_PRO|blocked|normal|Tower of Fantasy
com.blizzard.diablo.immortal|REDMAGIC_9_PRO|blocked|normal|Diablo Immortal
com.garena.game.df|REDMAGIC_9_PRO|blocked|normal|Delta Force Garena
com.proxima.dfm|ONEPLUS_13|blocked|normal|Delta Force Mobile
com.gameloft.android.ANMP.GloftA9HM|HONOR_MAGIC_V2_RSR|blocked|normal|Asphalt 9
com.mojang.minecraftpe|REDMAGIC_9_PRO|blocked|normal|Minecraft
TARGETS_EOF
    chmod 0600 "$TARGETS_FILE" 2>/dev/null
}

_init_cpu_blacklist(){
    [ -f "$CPU_BLACKLIST_FILE" ] && return 0
    cat > "$CPU_BLACKLIST_FILE" <<'CPU_BL_EOF'
com.bbl.mobilebanking
com.android.settings
com.android.vending
com.google.android.gms
com.google.android.apps.walletnfcrel
com.oplus.camera
com.android.camera
CPU_BL_EOF
    chmod 0600 "$CPU_BLACKLIST_FILE" 2>/dev/null
}

_init_cpuinfo(){
    [ -f "$CPUINFO_FILE" ] && return 0
    cat > "$CPUINFO_FILE" <<'CPUINFO_EOF'
Processor	: AArch64 Processor rev 1 (aarch64)
Hardware	: Qualcomm Technologies, Inc SM8750-AB
CPUINFO_EOF
    chmod 0600 "$CPUINFO_FILE" 2>/dev/null
}

_init_all(){
    mkdir -p "$BIN_DIR" 2>/dev/null
    _init_profiles
    _init_targets
    _init_cpu_blacklist
    _init_cpuinfo
}

_profile_exists(){
    _pid="$1"
    _valid_id "$_pid" || return 1
    grep -q "^${_pid}|" "$PROFILES_FILE" 2>/dev/null
}

_profile_count(){
    _init_profiles
    grep -v '^#' "$PROFILES_FILE" 2>/dev/null | grep -c '|' 2>/dev/null || printf '0'
}

_target_count(){
    _init_targets
    _n=0
    while IFS='|' read -r _pkg _profile _cpu _tweak _label _rest || [ -n "$_pkg" ]; do
        case "$_pkg" in ''|'#'*) continue ;; esac
        _valid_pkg "$_pkg" || continue
        _profile_exists "$_profile" || continue
        _n=$((_n+1))
    done < "$TARGETS_FILE"
    printf '%s' "$_n"
}

_cpu_only_count(){
    _init_targets
    _n=0
    while IFS='|' read -r _pkg _profile _cpu _tweak _label _rest || [ -n "$_pkg" ]; do
        case "$_pkg" in ''|'#'*) continue ;; esac
        _valid_pkg "$_pkg" || continue
        [ "$_cpu" = "cpu_only" ] && _n=$((_n+1))
    done < "$TARGETS_FILE"
    printf '%s' "$_n"
}

_blacklist_count(){
    _init_cpu_blacklist
    _n=0
    while IFS= read -r _pkg || [ -n "$_pkg" ]; do
        case "$_pkg" in ''|'#'*) continue ;; esac
        _valid_pkg "$_pkg" || continue
        _n=$((_n+1))
    done < "$CPU_BLACKLIST_FILE"
    printf '%s' "$_n"
}

_print_json_string_array_from_file(){
    _file="$1"
    _first=1
    while IFS= read -r _value || [ -n "$_value" ]; do
        case "$_value" in ''|'#'*) continue ;; esac
        _valid_pkg "$_value" || continue
        _esc=$(_json_escape "$_value")
        if [ "$_first" -eq 1 ]; then printf '      "%s"' "$_esc"; _first=0; else printf ',\n      "%s"' "$_esc"; fi
    done < "$_file"
    [ "$_first" -eq 0 ] && printf '\n'
}

_export_aio_json(){
    _tmp="${JSON_FILE}.tmp.$$"
    : > "$_tmp" || return 1
    if _spoof_enabled; then _enabled=true; else _enabled=false; fi
    {
        printf '{\n'
        printf '  "schema_version": 2,\n'
        printf '  "source": "AIO Ace5 COPG-inspired profile database",\n'
        printf '  "enabled": %s,\n' "$_enabled"
        printf '  "mode": "game_only_auto_profile",\n'
        printf '  "requires_companion": true,\n'
        printf '  "companion_type": "LSPosed_or_Zygisk",\n'
        printf '  "no_global_resetprop": true,\n'
        printf '  "cpu_spoof": {\n'
        printf '    "enabled": false,\n'
        printf '    "default_mode": "blocked",\n'
        printf '    "blacklist": [\n'
        _print_json_string_array_from_file "$CPU_BLACKLIST_FILE"
        printf '    ],\n'
        printf '    "cpuinfo_file": "%s"\n' "$CPUINFO_FILE"
        printf '  },\n'
        printf '  "profiles": {\n'
        _first_profile=1
        while IFS='|' read -r _pid _label _brand _manufacturer _device _product _model _fingerprint _board _hardware _rest || [ -n "$_pid" ]; do
            case "$_pid" in ''|'#'*) continue ;; esac
            _valid_id "$_pid" || continue
            if [ "$_first_profile" -eq 1 ]; then _first_profile=0; else printf ',\n'; fi
            printf '    "%s": {\n' "$(_json_escape "$_pid")"
            printf '      "label": "%s",\n' "$(_json_escape "$_label")"
            printf '      "BRAND": "%s",\n' "$(_json_escape "$_brand")"
            printf '      "MANUFACTURER": "%s",\n' "$(_json_escape "$_manufacturer")"
            printf '      "DEVICE": "%s",\n' "$(_json_escape "$_device")"
            printf '      "PRODUCT": "%s",\n' "$(_json_escape "$_product")"
            printf '      "MODEL": "%s",\n' "$(_json_escape "$_model")"
            printf '      "FINGERPRINT": "%s",\n' "$(_json_escape "$_fingerprint")"
            printf '      "BOARD": "%s",\n' "$(_json_escape "$_board")"
            printf '      "HARDWARE": "%s"\n' "$(_json_escape "$_hardware")"
            printf '    }'
        done < "$PROFILES_FILE"
        printf '\n  },\n'
        printf '  "targets": {\n'
        _first_target=1
        while IFS='|' read -r _pkg _profile _cpu _tweak _label _rest || [ -n "$_pkg" ]; do
            case "$_pkg" in ''|'#'*) continue ;; esac
            _valid_pkg "$_pkg" || continue
            _profile_exists "$_profile" || continue
            case "$_cpu" in blocked|with_cpu|cpu_only|notweak) ;; *) _cpu=blocked ;; esac
            case "$_tweak" in normal|minimal|none) ;; *) _tweak=normal ;; esac
            if [ "$_first_target" -eq 1 ]; then _first_target=0; else printf ',\n'; fi
            printf '    "%s": {"profile": "%s", "cpu": "%s", "tweak": "%s", "label": "%s"}' \
                "$(_json_escape "$_pkg")" "$(_json_escape "$_profile")" "$(_json_escape "$_cpu")" "$(_json_escape "$_tweak")" "$(_json_escape "$_label")"
        done < "$TARGETS_FILE"
        printf '\n  }\n'
        printf '}\n'
    } > "$_tmp" || { rm -f "$_tmp"; return 1; }
    mv -f "$_tmp" "$JSON_FILE" || { rm -f "$_tmp"; return 1; }
    chmod 0600 "$JSON_FILE" 2>/dev/null
    return 0
}

_export_copg_json(){
    _tmp="${COPG_JSON_FILE}.tmp.$$"
    : > "$_tmp" || return 1
    # COPG engine has no top-level enabled switch. When Game Spoof is OFF,
    # export an empty compatible config so the integrated Zygisk engine cannot spoof any package.
    if ! _spoof_enabled; then
        {
            printf '{\n'
            printf '  "cpu_spoof": {"blacklist": [], "cpu_only_packages": []}\n'
            printf '}\n'
        } > "$_tmp" || { rm -f "$_tmp"; return 1; }
        mv -f "$_tmp" "$COPG_JSON_FILE" || { rm -f "$_tmp"; return 1; }
        chmod 0600 "$COPG_JSON_FILE" 2>/dev/null
        return 0
    fi
    {
        printf '{\n'
        printf '  "cpu_spoof": {\n'
        printf '    "blacklist": [\n'
        _print_json_string_array_from_file "$CPU_BLACKLIST_FILE"
        printf '    ],\n'
        printf '    "cpu_only_packages": [\n'
        _first=1
        while IFS='|' read -r _pkg _profile _cpu _tweak _label _rest || [ -n "$_pkg" ]; do
            case "$_pkg" in ''|'#'*) continue ;; esac
            _valid_pkg "$_pkg" || continue
            [ "$_cpu" = "cpu_only" ] || continue
            if [ "$_first" -eq 1 ]; then printf '      "%s"' "$(_json_escape "$_pkg")"; _first=0; else printf ',\n      "%s"' "$(_json_escape "$_pkg")"; fi
        done < "$TARGETS_FILE"
        [ "$_first" -eq 0 ] && printf '\n'
        printf '    ]\n'
        printf '  }'
        while IFS='|' read -r _pid _label _brand _manufacturer _device _product _model _fingerprint _board _hardware _rest || [ -n "$_pid" ]; do
            case "$_pid" in ''|'#'*) continue ;; esac
            _valid_id "$_pid" || continue
            printf ',\n  "PACKAGES_%s": [\n' "$(_json_escape "$_pid")"
            _first_pkg=1
            while IFS='|' read -r _pkg _profile _cpu _tweak _tlabel _trest || [ -n "$_pkg" ]; do
                case "$_pkg" in ''|'#'*) continue ;; esac
                _valid_pkg "$_pkg" || continue
                [ "$_profile" = "$_pid" ] || continue
                case "$_cpu" in with_cpu) _tag="with_cpu" ;; cpu_only) _tag="with_cpu" ;; notweak) _tag="notweak" ;; *) _tag="blocked" ;; esac
                _entry="${_pkg}:${_tag}"
                if [ "$_first_pkg" -eq 1 ]; then printf '    "%s"' "$(_json_escape "$_entry")"; _first_pkg=0; else printf ',\n    "%s"' "$(_json_escape "$_entry")"; fi
            done < "$TARGETS_FILE"
            [ "$_first_pkg" -eq 0 ] && printf '\n'
            printf '  ],\n'
            printf '  "PACKAGES_%s_DEVICE": {\n' "$(_json_escape "$_pid")"
            printf '    "name": "%s",\n' "$(_json_escape "$_label")"
            printf '    "BRAND": "%s",\n' "$(_json_escape "$_brand")"
            printf '    "DEVICE": "%s",\n' "$(_json_escape "$_device")"
            printf '    "MANUFACTURER": "%s",\n' "$(_json_escape "$_manufacturer")"
            printf '    "MODEL": "%s",\n' "$(_json_escape "$_model")"
            printf '    "FINGERPRINT": "%s",\n' "$(_json_escape "$_fingerprint")"
            printf '    "PRODUCT": "%s"\n' "$(_json_escape "$_product")"
            printf '  }'
        done < "$PROFILES_FILE"
        printf '\n}\n'
    } > "$_tmp" || { rm -f "$_tmp"; return 1; }
    mv -f "$_tmp" "$COPG_JSON_FILE" || { rm -f "$_tmp"; return 1; }
    chmod 0600 "$COPG_JSON_FILE" 2>/dev/null
    return 0
}

_export_public(){
    mkdir -p /data/local/tmp 2>/dev/null
    cp -f "$JSON_FILE" "$PUBLIC_JSON" 2>/dev/null && chmod 0644 "$PUBLIC_JSON" 2>/dev/null
    cp -f "$COPG_JSON_FILE" "$PUBLIC_COPG_JSON" 2>/dev/null && chmod 0644 "$PUBLIC_COPG_JSON" 2>/dev/null
    cp -f "$CPUINFO_FILE" "$PUBLIC_CPUINFO" 2>/dev/null && chmod 0644 "$PUBLIC_CPUINFO" 2>/dev/null
}

_engine_abi_controller(){
    _abi="$(getprop ro.product.cpu.abi 2>/dev/null)"
    case "$_abi" in
        armeabi-v7a|armeabi) printf '%s' "$COPG_ENGINE_DIR/controller_armv7" ;;
        *) printf '%s' "$COPG_ENGINE_DIR/controller_arm64" ;;
    esac
}

_engine_available(){
    [ -f "$COPG_ZYGISK_ARM64" ] || return 1
    [ -f "$(_engine_abi_controller)" ] || [ -f "$COPG_ENGINE_DIR/controller_arm64" ] || return 1
    return 0
}

_is_external_copg_module(){
    [ -e "$COPG_COMPAT_DIR" ] || return 1
    [ -f "$COPG_COMPAT_MARKER" ] && return 1
    [ -f "$COPG_COMPAT_DIR/module.prop" ] && return 0
    [ -f "$COPG_COMPAT_JSON" ] || [ -f "$COPG_COMPAT_CPUINFO" ] || [ -f "$COPG_COMPAT_CONTROLLER" ]
    return $?
}

_is_aio_copg_shim(){
    [ -f "$COPG_COMPAT_MARKER" ] || return 1
    [ -f "$COPG_COMPAT_SIGNATURE" ] || return 1
    grep -qx 'AIO_Ace5_v3.1_COPG_SHIM' "$COPG_COMPAT_SIGNATURE" 2>/dev/null
}

_remove_aio_copg_shim(){
    _is_aio_copg_shim || return 0
    rm -f "$COPG_COMPAT_JSON" "$COPG_COMPAT_CPUINFO" "$COPG_COMPAT_CONTROLLER" \
        "$COPG_COMPAT_MARKER" "$COPG_COMPAT_SIGNATURE" 2>/dev/null
    rmdir "$COPG_COMPAT_DIR" 2>/dev/null
}

_stop_engine(){
    if [ -f "$COPG_CONTROLLER_PID" ]; then
        _pid="$(cat "$COPG_CONTROLLER_PID" 2>/dev/null | tr -d ' \t\n')"
        case "$_pid" in
            ''|*[!0-9]*) _log "controller pid missing" ;;
            *) kill "$_pid" 2>/dev/null && _log "controller killed pid=$_pid" || _log "controller pid missing" ;;
        esac
        rm -f "$COPG_CONTROLLER_PID" 2>/dev/null
    else
        _log "controller pid missing"
    fi
    rm -f "$PUBLIC_JSON" "$PUBLIC_COPG_JSON" "$PUBLIC_CPUINFO" 2>/dev/null
    if _is_aio_copg_shim; then
        _remove_aio_copg_shim && _log "AIO shim removed"
    elif _is_external_copg_module; then
        _log "external COPG detected, skip shim removal"
    fi
}

_setup_engine(){
    _engine_available || { _log "engine missing; zygisk/controller not bundled"; return 1; }
    if _is_external_copg_module; then
        _log "external COPG detected, skip shim"
        return 2
    fi
    mkdir -p "$COPG_COMPAT_DIR" 2>/dev/null || { _log "cannot create $COPG_COMPAT_DIR"; return 1; }
    printf 'AIO_Ace5_COPG_SHIM\n' > "$COPG_COMPAT_MARKER" 2>/dev/null || { _log "cannot create AIO shim marker"; return 1; }
    printf 'AIO_Ace5_v3.1_COPG_SHIM\n' > "$COPG_COMPAT_SIGNATURE" 2>/dev/null || { _log "cannot create AIO shim signature"; return 1; }
    cp -f "$COPG_JSON_FILE" "$COPG_COMPAT_JSON" 2>/dev/null || { _log "cannot copy COPG.json"; return 1; }
    cp -f "$CPUINFO_FILE" "$COPG_COMPAT_CPUINFO" 2>/dev/null || true
    _ctrl="$(_engine_abi_controller)"
    [ -f "$_ctrl" ] || _ctrl="$COPG_ENGINE_DIR/controller_arm64"
    cp -f "$_ctrl" "$COPG_COMPAT_CONTROLLER" 2>/dev/null || true
    chmod 0644 "$COPG_COMPAT_JSON" "$COPG_COMPAT_CPUINFO" 2>/dev/null
    chmod 0600 "$COPG_COMPAT_MARKER" "$COPG_COMPAT_SIGNATURE" 2>/dev/null
    chmod 0755 "$COPG_COMPAT_CONTROLLER" 2>/dev/null
    chcon u:object_r:system_file:s0 "$COPG_COMPAT_JSON" "$COPG_COMPAT_CPUINFO" "$COPG_COMPAT_CONTROLLER" 2>/dev/null || true
    if [ -x "$COPG_COMPAT_CONTROLLER" ]; then
        _old="$(cat "$COPG_CONTROLLER_PID" 2>/dev/null | tr -d ' \t\n')"
        case "$_old" in ''|*[!0-9]*) _old='' ;; esac
        if [ -n "$_old" ] && kill -0 "$_old" 2>/dev/null; then
            _log "controller already running pid=$_old"
        else
            "$COPG_COMPAT_CONTROLLER" >/dev/null 2>&1 &
            echo "$!" > "$COPG_CONTROLLER_PID" 2>/dev/null
            _log "controller started pid=$!"
        fi
    fi
    _log "AIO shim created"
    return 0
}

_export_all(){
    _init_all
    _export_aio_json || return 1
    _export_copg_json || return 1
    _export_public
    if _spoof_enabled; then
        _setup_engine >/dev/null 2>&1 || true
    else
        _stop_engine >/dev/null 2>&1 || true
    fi
    return 0
}

_status(){
    _init_all
    if [ ! -f "$JSON_FILE" ] || [ ! -f "$COPG_JSON_FILE" ]; then
        _export_all >/dev/null 2>&1 || true
    fi
    if _spoof_enabled; then _state="on"; else _state="off"; fi
    printf 'INFO_GAME_SPOOF=%s\n' "$_state"
    printf 'INFO_GAME_SPOOF_MODE=auto_by_game\n'
    printf 'INFO_GAME_SPOOF_PROFILES=%s\n' "$(_profile_count)"
    printf 'INFO_GAME_SPOOF_TARGETS=%s\n' "$(_target_count)"
    printf 'INFO_GAME_SPOOF_CPU_ONLY=%s\n' "$(_cpu_only_count)"
    printf 'INFO_GAME_SPOOF_CPU_BLACKLIST=%s\n' "$(_blacklist_count)"
    if _engine_available; then _engine="bundled_copg_zygisk"; else _engine="missing"; fi
    if _is_external_copg_module; then
        _engine_state="external_copg_detected"
    elif _is_aio_copg_shim && [ -f "$COPG_COMPAT_JSON" ]; then
        _engine_state="ready"
    else
        _engine_state="inactive"
    fi
    printf 'INFO_GAME_SPOOF_COMPANION=%s\n' "$_engine"
    printf 'INFO_GAME_SPOOF_ENGINE_STATE=%s\n' "$_engine_state"
    printf 'INFO_GAME_SPOOF_ENGINE_PATH=%s\n' "$COPG_COMPAT_DIR"
    printf 'INFO_GAME_SPOOF_CONFIG=%s\n' "$JSON_FILE"
    printf 'INFO_GAME_SPOOF_COPG_COMPAT=%s\n' "$COPG_JSON_FILE"
    printf 'INFO_GAME_SPOOF_PUBLIC_CONFIG=%s\n' "$PUBLIC_JSON"
}

_enable(){
    _init_all
    _ensure_state_dir
    : > "$FLAG" || { printf '[ERR] Không tạo được flag Game Spoof.\n'; return 1; }
    chmod 0600 "$FLAG" 2>/dev/null
    if _export_all; then
        _log "enabled mode=auto_by_game profiles=$(_profile_count) targets=$(_target_count) config=$JSON_FILE copg=$COPG_JSON_FILE"
        printf '[OK] Đã bật cấu hình Game Spoof theo từng game.\n'
        printf '[INFO] Profiles: %s | Targets: %s | CPU-only: %s | CPU blacklist: %s\n' "$(_profile_count)" "$(_target_count)" "$(_cpu_only_count)" "$(_blacklist_count)"
        printf '[INFO] Config AIO: %s\n' "$JSON_FILE"
        printf '[INFO] COPG-compatible config: %s\n' "$COPG_JSON_FILE"
        if _engine_available; then
            printf '[OK] Engine spoof COPG-compatible đã được nhúng. Cần bật Zygisk/ReZygisk/Zygisk Next và reboot để engine load vào game.\n'
            printf '[INFO] Game đang chạy cần force-stop/mở lại để nhận spoof.\n'
        else
            printf '[WARN] Thiếu engine Zygisk; chỉ mới xuất config.\n'
        fi
        _status
        return 0
    fi
    printf '[ERR] Không xuất được cấu hình Game Spoof.\n'
    return 1
}

_disable(){
    rm -f "$FLAG" 2>/dev/null
    rm -f "$OLD_FLAG" 2>/dev/null
    if _export_all; then
        _log "disabled mode=auto_by_game"
        printf '[OK] Đã tắt cấu hình Game Spoof.\n'
        printf '[INFO] Đã xóa config COPG runtime; game đang chạy cần force-stop/mở lại để hết spoof.\n'
        _status
        return 0
    fi
    printf '[ERR] Không cập nhật được cấu hình Game Spoof.\n'
    return 1
}

case "${1:-}" in
    --enable)
        aio_log game_spoof INFO START action=enable
        _enable; _rc=$?
        if [ "$_rc" -eq 0 ]; then aio_log game_spoof SUMMARY done action=enable status=ok; else aio_log game_spoof ERR failed action=enable status=error rc=$_rc; fi
        exit "$_rc"
        ;;
    --disable)
        aio_log game_spoof INFO START action=disable
        _disable; _rc=$?
        if [ "$_rc" -eq 0 ]; then aio_log game_spoof SUMMARY done action=disable status=ok; else aio_log game_spoof ERR failed action=disable status=error rc=$_rc; fi
        exit "$_rc"
        ;;
    --status) _status ;;
    --export|--service)
        aio_log game_spoof INFO START action=export
        _export_all; _rc=$?
        if [ "$_rc" -eq 0 ]; then
            printf '[OK] Exported: %s\n' "$JSON_FILE"
            printf '[OK] COPG-compatible: %s\n' "$COPG_JSON_FILE"
            _status
            aio_log game_spoof SUMMARY done action=export status=ok
        else
            aio_log game_spoof ERR failed action=export status=error rc=$_rc
        fi
        exit "$_rc"
        ;;
    *)
        printf 'Usage: %s --enable|--disable|--status|--export|--service\n' "$0"
        exit 1
        ;;
esac
