#!/system/bin/sh
# AIO Ace5 v3.1 batch Debloat

MODDIR="${0%/*}/.."
CATALOG_FILE="$MODDIR/bin/debloat_catalog.conf"
BACKUP_FILE="$MODDIR/bin/debloat_backup.list"
COOLDOWN_FLAG="$MODDIR/bin/cooldown_enabled.flag"
COOLDOWN_BACKUP_FILE="$MODDIR/bin/cooldown_backup.list"
TOUCH360_FLAG="$MODDIR/bin/touch_360_enabled.flag"
TOUCH360_WORKER="$MODDIR/bin/touch_360_worker.sh"
TOUCH360_PID="$MODDIR/bin/touch_360_worker.pid"
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

log_info() { printf '[INFO] %s\n' "$*"; }
log_ok()   { printf '[OK] %s\n' "$*"; }
log_warn() { [ -n "${_WARN+x}" ] && _WARN=$((_WARN + 1)); printf '[WARN] %s\n' "$*"; }
log_err()  { printf '[ERR] %s\n' "$*"; }
log_skip() { printf '[SKIP] %s\n' "$*"; }
log_run()  { printf '[Đang chạy] %s\n' "$*"; }

_now() { date +%s 2>/dev/null || printf '0'; }
_duration() { _end="$(_now)"; printf '%s' $((_end - _START_TS)); }
_cooldown_state() { [ -f "$COOLDOWN_FLAG" ] && printf 'on' || printf 'off'; }
_touch360_state() { [ -f "$TOUCH360_FLAG" ] && printf 'on' || printf 'off'; }
_touch360_worker_state() {
    _pid=""
    [ -f "$TOUCH360_PID" ] && _pid="$(cat "$TOUCH360_PID" 2>/dev/null | tr -d ' \t\n')"
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then printf 'running'; else printf 'stopped'; fi
}
_backup_count() { [ -f "$BACKUP_FILE" ] && awk 'NF{n++} END{print n+0}' "$BACKUP_FILE" 2>/dev/null || printf '0'; }

_is_valid_pkg() {
    case "${1:-}" in
        ''|.*|*.|*..*|*[!a-zA-Z0-9_.]*) return 1 ;;
    esac
    return 0
}

_ensure_catalog() {
    [ -f "$CATALOG_FILE" ] || { log_err "missing catalog: $CATALOG_FILE"; exit 1; }
}

_ensure_backup() {
    mkdir -p "${BACKUP_FILE%/*}" 2>/dev/null
    [ -f "$BACKUP_FILE" ] || : > "$BACKUP_FILE" 2>/dev/null || {
        log_err "cannot write backup: $BACKUP_FILE"
        exit 1
    }
}

_backup_has() {
    [ -f "$BACKUP_FILE" ] || return 1
    awk -F'|' -v p="$1" '$1==p{found=1} END{exit !found}' "$BACKUP_FILE" 2>/dev/null
}

_backup_add() {
    _pkg="$1"; _action="$2"; _section="$3"
    _backup_has "$_pkg" && return 0
    printf '%s|%s|%s|%s\n' "$_pkg" "$_action" "$_section" "$(_now)" >> "$BACKUP_FILE"
}

_backup_remove() {
    _pkg="$1"
    [ -f "$BACKUP_FILE" ] || return 0
    _tmp="/data/local/tmp/ca5_debloat_backup_$$.tmp"
    awk -F'|' -v p="$_pkg" '$1!=p{print}' "$BACKUP_FILE" > "$_tmp" 2>/dev/null \
        && mv "$_tmp" "$BACKUP_FILE" 2>/dev/null \
        || rm -f "$_tmp" 2>/dev/null
}

_cooldown_backup_has() {
    _type="$1"; _name="$2"
    [ -f "$COOLDOWN_BACKUP_FILE" ] || return 1
    awk -F'|' -v t="$_type" -v n="$_name" '$1==t && $2==n{found=1} END{exit !found}' "$COOLDOWN_BACKUP_FILE" 2>/dev/null
}

_cooldown_backup_add() {
    _type="$1"; _name="$2"; _state="$3"; _value="$4"
    _cooldown_backup_has "$_type" "$_name" && return 0
    if [ "$_type" = "PROP" ]; then
        printf 'PROP|%s|%s|%s\n' "$_name" "$_state" "$_value" >> "$COOLDOWN_BACKUP_FILE"
    else
        printf 'PKG|%s|%s\n' "$_name" "$_state" >> "$COOLDOWN_BACKUP_FILE"
    fi
}

_pkg_exists() {
    pm path "$1" >/dev/null 2>&1 || pm list packages -u 2>/dev/null | grep -qxF "package:$1"
}

_pkg_state() {
    _pkg="$1"
    _pkg_exists "$_pkg" || { printf 'not_installed'; return 0; }
    pm list packages -d --user 0 "$_pkg" 2>/dev/null | grep -qxF "package:$_pkg" && { printf 'disabled'; return 0; }
    pm list packages -e --user 0 "$_pkg" 2>/dev/null | grep -qxF "package:$_pkg" && { printf 'enabled'; return 0; }
    printf 'unknown'
}

_pkg_installed_user0() {
    _out="$(pm list packages --user 0 "$1" 2>/dev/null)"
    [ -n "$_out" ] || _out="$(pm list packages "$1" 2>/dev/null)"
    printf '%s\n' "$_out" | grep -qxF "package:$1"
}

_mount_has() {
    _target="$1"
    mount | awk -v t="$_target" '$2==t{found=1} END{exit !found}' 2>/dev/null
}

_cooldown_unmount_stubs() {
    for _t in /system/bin/logd /system/bin/logcat /system/bin/update_engine /system/bin/update_engine_sideload; do
        if _mount_has "$_t"; then
            if umount "$_t" 2>/dev/null; then log_ok "Cooldown unmounted: $_t"; else log_warn "Cooldown unmount failed: $_t"; fi
        else
            log_skip "Cooldown mount not active: $_t"
        fi
    done
}

_cooldown_restore_props() {
    if [ -f "$COOLDOWN_BACKUP_FILE" ]; then
        while IFS='|' read -r _type _k _state _v; do
            [ "$_type" = "PROP" ] || continue
            case "$_k" in ''|*[!a-zA-Z0-9_.-]*) log_skip "Cooldown prop invalid: $_k"; continue ;; esac
            case "$_state" in
                value) setprop "$_k" "$_v" 2>/dev/null && log_ok "Cooldown prop restored: $_k=$_v" || log_skip "Cooldown prop skipped: $_k" ;;
                empty) setprop "$_k" "" 2>/dev/null && log_ok "Cooldown prop restored empty: $_k" || log_skip "Cooldown empty prop skipped: $_k" ;;
                *) log_skip "Cooldown prop unknown, skip: $_k" ;;
            esac
        done < "$COOLDOWN_BACKUP_FILE"
    else
        log_warn "missing cooldown backup; skip hardcoded prop restore"
    fi
    setprop ctl.start logd 2>/dev/null && log_ok "Cooldown service start: logd" || log_skip "Cooldown service start skipped: logd"
    setprop ctl.start update_engine 2>/dev/null && log_ok "Cooldown service start: update_engine" || log_skip "Cooldown service start skipped: update_engine"
}

_cooldown_prop_exists() {
    _key="$1"
    getprop 2>/dev/null | grep -F "[$_key]:" >/dev/null 2>&1
}

_cooldown_prop_keys() {
    printf '%s\n' \
        persist.logd.enable \
        persist.logd.logpersistd.enable \
        persist.logd.flowctrl.on \
        persist.logd.size \
        persist.ota.auto_download \
        persist.sys.recovery_update \
        persist.sys.coupdate \
        persist.sys.sota.state \
        sys.oplus.production.wifi.ota \
        persist.sys.oplus.ad_enable \
        persist.sys.oplus.personalized_ad \
        persist.ad.track \
        persist.sys.enable_ad_logdump \
        persist.sys.usage_stat_enable \
        persist.oppo.collect \
        persist.sys.oppo.junkmonitor \
        persist.sys.preload \
        persist.vendor.enable.preload \
        persist.sys.monitor \
        persist.sys.hotstart \
        sys.oplus.respreload.vipcsdk.enabled \
        persist.sys.oplus.theia_screen_monitor.disabled \
        persist.sys.fflag.override.settings_enable_monitor_phantom_procs
}

_cooldown_snapshot() {
    _ensure_catalog
    mkdir -p "${COOLDOWN_BACKUP_FILE%/*}" 2>/dev/null
    if [ -f "$COOLDOWN_FLAG" ]; then
        if [ -s "$COOLDOWN_BACKUP_FILE" ]; then
            log_skip "Cooldown already enabled; keep existing backup: $COOLDOWN_BACKUP_FILE"
        else
            log_warn "Cooldown already enabled but backup missing; do not snapshot current changed state"
        fi
        return 0
    fi
    : > "$COOLDOWN_BACKUP_FILE" 2>/dev/null || { log_warn "cannot write cooldown backup"; return 0; }
    log_info "Cooldown backup path: $COOLDOWN_BACKUP_FILE"
    while IFS='|' read -r _pkg _section _action _default _label _desc; do
        case "$_pkg" in ''|\#*) continue ;; esac
        [ "$_section" = "cooldown" ] || continue
        if ! _is_valid_pkg "$_pkg"; then
            log_warn "skip invalid package name from catalog: $_pkg"
            continue
        fi
        _cooldown_backup_add PKG "$_pkg" "$(_pkg_state "$_pkg")"
    done < "$CATALOG_FILE"
    _cooldown_prop_keys | while IFS= read -r _k; do
        if _cooldown_prop_exists "$_k"; then
            _v="$(getprop "$_k" 2>/dev/null)"
            if [ -n "$_v" ]; then
                _cooldown_backup_add PROP "$_k" value "$_v"
            else
                _cooldown_backup_add PROP "$_k" empty ""
            fi
        else
            _cooldown_backup_add PROP "$_k" unknown ""
        fi
    done
    log_info "Cooldown snapshot packages: $(awk -F'|' '$1=="PKG"{n++} END{print n+0}' "$COOLDOWN_BACKUP_FILE" 2>/dev/null)"
    log_info "Cooldown snapshot props: $(awk -F'|' '$1=="PROP"{n++} END{print n+0}' "$COOLDOWN_BACKUP_FILE" 2>/dev/null)"
}

_summary() {
    printf 'SUMMARY_OK=%s\n' "$_OK"
    printf 'SUMMARY_WARN=%s\n' "$_WARN"
    printf 'SUMMARY_ERR=%s\n' "$_ERR"
    printf 'SUMMARY_SKIP=%s\n' "$_SKIP"
    printf 'SUMMARY_TOTAL=%s\n' "$_TOTAL"
    printf 'SUMMARY_BACKUP=%s\n' "$(_backup_count)"
    printf 'SUMMARY_COOLDOWN=%s\n' "$(_cooldown_state)"
    printf 'SUMMARY_TOUCH360=%s\n' "$(_touch360_state)"
    printf 'SUMMARY_TOUCH360_WORKER=%s\n' "$(_touch360_worker_state)"
    printf 'SUMMARY_DURATION=%s\n' "$(_duration)"
}

_catalog_counts() {
    awk -F'|' '
        $1 !~ /^#/ && NF==6 {
            total++
            if ($2=="recommended") recommended++
            else if ($2=="optional") optional++
            else if ($2=="cooldown") cooldown++
        }
        END {
            printf "total=%d recommended=%d optional=%d cooldown=%d\n", total+0, recommended+0, optional+0, cooldown+0
        }
    ' "$CATALOG_FILE"
}

_section_count() {
    _section="$1"
    awk -F'|' -v s="$_section" '$1 !~ /^#/ && NF==6 && $2==s {n++} END{print n+0}' "$CATALOG_FILE" 2>/dev/null
}

_pm_disable() {
    _pkg="$1"
    _out="$(pm disable-user --user 0 "$_pkg" 2>&1)"
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        case "$_out" in *"not installed"*|*"Unknown package"*|*"Unable to find"*|*"NameNotFoundException"*|*"doesn't exist"*) return 2 ;; esac
        log_err "$_pkg: $_out"
        return 1
    fi
    [ -n "$_out" ] && case "$_out" in *Warning*|*warning*) log_warn "$_pkg: $_out" ;; esac
    return 0
}

_pm_uninstall() {
    _pkg="$1"
    _out="$(pm uninstall -k --user 0 "$_pkg" 2>&1)"
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        case "$_out" in *"not installed"*|*"Unknown package"*|*"Unable to find"*|*"NameNotFoundException"*|*"doesn't exist"*) return 2 ;; esac
        log_err "$_pkg: $_out"
        return 1
    fi
    [ -n "$_out" ] && case "$_out" in *Warning*|*warning*) log_warn "$_pkg: $_out" ;; esac
    if _pkg_installed_user0 "$_pkg"; then
        log_warn "$_pkg: uninstall attempted but package still present for user 0"
            aio_log debloat WARN uninstall_verify package=$_pkg status=still_present_user0
        return 3
    fi
    return 0
}

_pm_enable() {
    _pkg="$1"
    _out="$(pm enable --user 0 "$_pkg" 2>&1)"
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        case "$_out" in *"not installed"*|*"Unknown package"*|*"Unable to find"*|*"NameNotFoundException"*|*"doesn't exist"*) return 2 ;; esac
        log_err "$_pkg: $_out"
        return 1
    fi
    [ -n "$_out" ] && case "$_out" in *Warning*|*warning*) log_warn "$_pkg: $_out" ;; esac
    return 0
}

_pm_install_existing() {
    _pkg="$1"
    _out="$(cmd package install-existing --user 0 "$_pkg" 2>&1)"
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        case "$_out" in *"not installed"*|*"Unknown package"*|*"Unable to find"*|*"NameNotFoundException"*|*"doesn't exist"*) return 2 ;; esac
        _out2="$(pm install-existing --user 0 "$_pkg" 2>&1)"
        _rc2=$?
        if [ "$_rc2" -ne 0 ]; then
            case "$_out2" in *"not installed"*|*"Unknown package"*|*"Unable to find"*|*"NameNotFoundException"*|*"doesn't exist"*) return 2 ;; esac
            log_err "$_pkg: $_out / $_out2"
            return 1
        fi
        [ -n "$_out2" ] && case "$_out2" in *Warning*|*warning*) log_warn "$_pkg: $_out2" ;; esac
        return 0
    fi
    [ -n "$_out" ] && case "$_out" in *Warning*|*warning*) log_warn "$_pkg: $_out" ;; esac
    return 0
}

_touch360_find_bin() {
    for p in /system/bin/touchHidlTest /system_ext/bin/touchHidlTest /vendor/bin/touchHidlTest /odm/bin/touchHidlTest; do
        [ -x "$p" ] && { printf '%s' "$p"; return 0; }
    done
    command -v touchHidlTest 2>/dev/null && return 0
    return 1
}

_touch360_restore_default() {
    _bin="$(_touch360_find_bin)" || return 2
    "$_bin" -c wo 0 182 0 >/dev/null 2>&1 || return 1
    return 0
}

_touch360_stop_worker() {
    _pid=""
    [ -f "$TOUCH360_PID" ] && _pid="$(cat "$TOUCH360_PID" 2>/dev/null | tr -d ' \t\n')"
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        kill -TERM "$_pid" 2>/dev/null
        _i=0
        while [ "$_i" -lt 3 ]; do
            kill -0 "$_pid" 2>/dev/null || break
            sleep 1
            _i=$((_i + 1))
        done
        kill -0 "$_pid" 2>/dev/null && kill -9 "$_pid" 2>/dev/null
    fi
    rm -f "$TOUCH360_PID" /data/local/tmp/aio_touch360.state 2>/dev/null
}

_touch360_start_worker() {
    [ -f "$TOUCH360_WORKER" ] || { log_err "touch360 worker not found: $TOUCH360_WORKER"; return 1; }
    chmod 0755 "$TOUCH360_WORKER" 2>/dev/null
    if [ "$(_touch360_worker_state)" = "running" ]; then
        log_ok "Touch 360Hz worker already running"
        return 0
    fi
    nohup /system/bin/sh "$TOUCH360_WORKER" >/dev/null 2>&1 &
    sleep 1
    if [ "$(_touch360_worker_state)" = "running" ]; then
        log_ok "Touch 360Hz worker started"
        return 0
    fi
    log_warn "Touch 360Hz flag enabled but worker status not confirmed"
    return 0
}

_touch360_enable() {
    _START_TS="$(_now)"; _OK=0; _WARN=0; _ERR=0; _SKIP=0; _TOTAL=0
    log_run "1/1 Touch 360Hz auto"
    _TOTAL=1
    mkdir -p "${TOUCH360_FLAG%/*}" 2>/dev/null
    : > "$TOUCH360_FLAG" 2>/dev/null || { log_err "cannot write touch360 flag"; _ERR=1; _summary; return 1; }
    _touch360_start_worker; _rc=$?
    if [ "$_rc" -eq 0 ]; then
        log_ok "Touch 360Hz auto ON"
        log_info "Ep 360Hz khi cong tac ON; lap lai dinh ky. Tat cong tac de restore mac dinh."
        _OK=1
    else
        _ERR=1
    fi
    _summary
    [ "$_ERR" -gt 0 ] && return 1 || return 0
}

_touch360_disable() {
    _START_TS="$(_now)"; _OK=0; _WARN=0; _ERR=0; _SKIP=0; _TOTAL=0
    log_run "1/1 Touch 360Hz auto"
    _TOTAL=1
    rm -f "$TOUCH360_FLAG" 2>/dev/null
    _touch360_stop_worker
    _touch360_restore_default; _rc=$?
    case "$_rc" in
        0) log_ok "Touch 360Hz auto OFF, restored default"; _OK=1 ;;
        2) log_skip "touchHidlTest not found, flag OFF"; _SKIP=1 ;;
        *) log_warn "restore default failed, flag OFF"; _WARN=1 ;;
    esac
    _summary
    [ "$_ERR" -gt 0 ] && return 1 || return 0
}

_process_pkg() {
    _pkg="$1"; _section="$2"; _action="$3"; _idx="$4"; _total="$5"
    if ! _is_valid_pkg "$_pkg"; then
        log_warn "skip invalid package name from catalog: $_pkg"
        _SKIP=$((_SKIP + 1))
        return 0
    fi
    log_run "$_idx/$_total $_pkg"
    _TOTAL=$((_TOTAL + 1))

    if ! _pkg_exists "$_pkg"; then
        log_skip "$_pkg: not found / not installed"
        _SKIP=$((_SKIP + 1))
        return 0
    fi

    case "$_action" in
        uninstall)
            am force-stop "$_pkg" 2>/dev/null
            pm disable-user --user 0 "$_pkg" >/dev/null 2>&1
            _pm_uninstall "$_pkg"; _rc=$?
            ;;
        disable|cooldown)
            am force-stop "$_pkg" 2>/dev/null
            _pm_disable "$_pkg"; _rc=$?
            ;;
        *) log_err "$_pkg: invalid action $_action"; _rc=1 ;;
    esac

    case "$_rc" in
        0) _backup_add "$_pkg" "$_action" "$_section"; log_ok "$_pkg"; _OK=$((_OK + 1)) ;;
        2) log_skip "$_pkg: not found / not installed"; _SKIP=$((_SKIP + 1)) ;;
        3) _backup_add "$_pkg" "$_action" "$_section"; _WARN=$((_WARN + 1)) ;;
        *) _ERR=$((_ERR + 1)) ;;
    esac
}

_run_catalog() {
    _filter="$1"; _total_expected="$2"; _force_action="$3"; _idx_start="$4"
    _idx="$_idx_start"
    while IFS='|' read -r _pkg _section _action _default _label _desc; do
        case "$_pkg" in ''|\#*) continue ;; esac
        [ "$_section" = "$_filter" ] || continue
        _idx=$((_idx + 1))
        [ -n "$_force_action" ] && _action="$_force_action"
        _process_pkg "$_pkg" "$_section" "$_action" "$_idx" "$_total_expected"
    done < "$CATALOG_FILE"
}

_apply_recommended() {
    _START_TS="$(_now)"; _OK=0; _WARN=0; _ERR=0; _SKIP=0; _TOTAL=0
    _ensure_catalog; _ensure_backup
    _count="$(_section_count recommended)"
    _run_catalog recommended "$_count" "uninstall" 0
    _summary
    [ "$_ERR" -gt 0 ] && exit 1 || exit 0
}

_apply_deep() {
    log_warn "--apply-deep da bo, chuyen ve DEBLOAT list da chot"
    _apply_recommended
}

_restore_all() {
    _START_TS="$(_now)"; _OK=0; _WARN=0; _ERR=0; _SKIP=0; _TOTAL=0
    _ensure_catalog; _ensure_backup
    _count="$(_section_count recommended)"
    _idx=0
    while IFS='|' read -r _pkg _section _action _default _label _desc; do
        case "$_pkg" in ''|\#*) continue ;; esac
        if ! _is_valid_pkg "$_pkg"; then log_warn "skip invalid package name from catalog: $_pkg"; _SKIP=$((_SKIP + 1)); continue; fi
        [ "$_section" = "recommended" ] || continue
        _idx=$((_idx + 1))
        log_run "$_idx/$_count $_pkg"
        _TOTAL=$((_TOTAL + 1))
        _pm_install_existing "$_pkg"; _rc=$?
        if [ "$_rc" -eq 0 ]; then
            _pm_enable "$_pkg"; _rc2=$?
            case "$_rc2" in
                0|2) _backup_remove "$_pkg"; log_ok "$_pkg"; _OK=$((_OK + 1)) ;;
                *) _ERR=$((_ERR + 1)) ;;
            esac
        else
            case "$_rc" in
                2) log_skip "$_pkg: not found / not installed"; _SKIP=$((_SKIP + 1)); _backup_remove "$_pkg" ;;
                *) _ERR=$((_ERR + 1)) ;;
            esac
        fi
    done < "$CATALOG_FILE"
    _summary
    [ "$_ERR" -gt 0 ] && exit 1 || exit 0
}

_cooldown_enable() {
    _quiet="$1"
    _START_TS="$(_now)"; _OK=0; _WARN=0; _ERR=0; _SKIP=0; _TOTAL=0
    _ensure_catalog; _ensure_backup
    _cooldown_snapshot
    _count="$(_section_count cooldown)"
    _run_catalog cooldown "$_count" cooldown 0
    : > "$COOLDOWN_FLAG" 2>/dev/null || log_warn "cannot write cooldown flag"
    [ "$_quiet" = "quiet" ] || _summary
    [ "$_ERR" -gt 0 ] && return 1 || return 0
}

_cooldown_disable() {
    _quiet="$1"
    _START_TS="$(_now)"; _OK=0; _WARN=0; _ERR=0; _SKIP=0; _TOTAL=0
    _ensure_catalog; _ensure_backup
    _count="$(awk -F'|' '$1=="PKG"{n++} END{print n+0}' "$COOLDOWN_BACKUP_FILE" 2>/dev/null)"
    [ "$_count" -gt 0 ] 2>/dev/null || _count="$(_section_count cooldown)"
    _idx=0
    if [ -f "$COOLDOWN_BACKUP_FILE" ] && [ -s "$COOLDOWN_BACKUP_FILE" ]; then
        log_info "Cooldown restore backup: $COOLDOWN_BACKUP_FILE"
        while IFS='|' read -r _type _pkg _state _rest; do
            [ "$_type" = "PKG" ] || continue
            if ! _is_valid_pkg "$_pkg"; then log_warn "skip invalid package name from cooldown backup: $_pkg"; _SKIP=$((_SKIP + 1)); continue; fi
            _idx=$((_idx + 1))
            log_run "$_idx/$_count $_pkg"
            _TOTAL=$((_TOTAL + 1))
            case "$_state" in
                enabled)
                    _pm_enable "$_pkg"; _rc=$?
                    case "$_rc" in
                        0) log_ok "$_pkg: restored enabled"; _OK=$((_OK + 1)) ;;
                        2) log_skip "$_pkg: not found / not installed"; _SKIP=$((_SKIP + 1)) ;;
                        *) _ERR=$((_ERR + 1)) ;;
                    esac
                    ;;
                disabled)
                    _pm_disable "$_pkg"; _rc=$?
                    case "$_rc" in
                        0) log_ok "$_pkg: restored disabled"; _OK=$((_OK + 1)) ;;
                        2) log_skip "$_pkg: not found / not installed"; _SKIP=$((_SKIP + 1)) ;;
                        *) _ERR=$((_ERR + 1)) ;;
                    esac
                    ;;
                not_installed)
                    log_skip "$_pkg: was not installed before Cooldown"
                    _SKIP=$((_SKIP + 1))
                    ;;
                *)
                    log_skip "$_pkg: unknown original state"
                    _SKIP=$((_SKIP + 1))
                    ;;
            esac
        done < "$COOLDOWN_BACKUP_FILE"
    else
        log_warn "missing cooldown backup; skip package restore to avoid wrong state"
    fi
    _cooldown_unmount_stubs
    _cooldown_restore_props
    if [ -f "$COOLDOWN_BACKUP_FILE" ]; then
        mv "$COOLDOWN_BACKUP_FILE" "$COOLDOWN_BACKUP_FILE.last" 2>/dev/null || log_skip "Cooldown backup archive skipped"
    fi
    rm -f "$COOLDOWN_FLAG" 2>/dev/null
    [ "$_quiet" = "quiet" ] || _summary
    [ "$_ERR" -gt 0 ] && return 1 || return 0
}

case "${1:-}" in
    --info)
        _ensure_catalog
        printf 'INFO %s\n' "$(_catalog_counts)"
        printf 'INFO_COOLDOWN=%s\n' "$(_cooldown_state)"
        printf 'INFO_TOUCH360=%s\n' "$(_touch360_state)"
        printf 'INFO_TOUCH360_WORKER=%s\n' "$(_touch360_worker_state)"
        printf 'INFO_DEBLOAT_COUNT=%s\n' "$(_section_count recommended)"
        printf 'INFO_COOLDOWN_COUNT=%s\n' "$(_section_count cooldown)"
        ;;
    --count)
        _ensure_catalog
        printf 'COUNT %s\n' "$(_catalog_counts)"
        printf 'COUNT_DEBLOAT=%s\n' "$(_section_count recommended)"
        printf 'COUNT_COOLDOWN=%s\n' "$(_section_count cooldown)"
        ;;
    --apply-recommended)
        aio_log debloat INFO START action=apply_recommended
        _apply_recommended; _rc=$?
        if [ "$_rc" -eq 0 ]; then aio_log debloat SUMMARY done action=apply_recommended status=ok; else aio_log debloat ERR failed action=apply_recommended status=error rc=$_rc; fi
        exit "$_rc"
        ;;
    --apply-deep|--apply-heavy)
        aio_log debloat INFO START action=apply_deep
        _apply_deep; _rc=$?
        if [ "$_rc" -eq 0 ]; then aio_log debloat SUMMARY done action=apply_deep status=ok; else aio_log debloat ERR failed action=apply_deep status=error rc=$_rc; fi
        exit "$_rc"
        ;;
    --restore-all)
        aio_log debloat INFO START action=restore_all
        _restore_all; _rc=$?
        if [ "$_rc" -eq 0 ]; then aio_log debloat SUMMARY done action=restore_all status=ok; else aio_log debloat ERR failed action=restore_all status=error rc=$_rc; fi
        exit "$_rc"
        ;;
    --cooldown-enable)
        aio_log debloat INFO START action=cooldown_enable
        _cooldown_enable; _rc=$?
        if [ "$_rc" -eq 0 ]; then aio_log debloat SUMMARY done action=cooldown_enable status=ok; else aio_log debloat ERR failed action=cooldown_enable status=error rc=$_rc; fi
        exit "$_rc"
        ;;
    --cooldown-disable)
        aio_log debloat INFO START action=cooldown_disable
        _cooldown_disable; _rc=$?
        if [ "$_rc" -eq 0 ]; then aio_log debloat SUMMARY done action=cooldown_disable status=ok; else aio_log debloat ERR failed action=cooldown_disable status=error rc=$_rc; fi
        exit "$_rc"
        ;;
    --touch360-enable)
        aio_log debloat INFO START action=touch360_enable
        _touch360_enable; _rc=$?
        if [ "$_rc" -eq 0 ]; then aio_log debloat SUMMARY done action=touch360_enable status=ok; else aio_log debloat ERR failed action=touch360_enable status=error rc=$_rc; fi
        exit "$_rc"
        ;;
    --touch360-disable)
        aio_log debloat INFO START action=touch360_disable
        _touch360_disable; _rc=$?
        if [ "$_rc" -eq 0 ]; then aio_log debloat SUMMARY done action=touch360_disable status=ok; else aio_log debloat ERR failed action=touch360_disable status=error rc=$_rc; fi
        exit "$_rc"
        ;;
    *)
        log_err "unknown command: ${1:-<none>}"
        log_info "use: --info | --count | --apply-recommended | --apply-deep | --restore-all | --cooldown-enable | --cooldown-disable | --touch360-enable | --touch360-disable"
        exit 1
        ;;
esac
