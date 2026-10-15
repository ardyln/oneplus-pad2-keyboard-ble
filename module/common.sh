#!/system/bin/sh
# Shared helpers. Caller sets MODDIR before sourcing.

. "$MODDIR/config.sh"

# ---- The keyboard's Bluetooth address ----------------------------------------------------------
# Found in this order, so nobody has to look it up:
#   1. config.sh KBD_MAC (for builds made for one keyboard)
#   2. $STATE_DIR/keyboard_mac, written by the user to pin a keyboard (survives module updates)
#   3. the pogo driver's frames in the kernel log, sent about every 100 ms while a keyboard is
#      attached ("... f1 a1 a2 2f 0b 05 02 00 03 <address, little-endian> ..."), so a different
#      keyboard is picked up as soon as it's attached
#   4. the last address found that way ($STATE_DIR/keyboard_mac.detected)
#   5. the only paired OnePlus keyboard (vendor/product id) in bt_config.conf
# KBD_MAC_SOURCE says which one was used; KBD_MAC stays empty if none worked.
MAC_OVERRIDE_FILE=$STATE_DIR/keyboard_mac
MAC_DETECTED_FILE=$STATE_DIR/keyboard_mac.detected

_awk() { if [ -n "$BB" ]; then "$BB" awk "$@"; else awk "$@"; fi; }

valid_mac() { echo "$1" | grep -qiE '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; }

mac_from_pogo() {
    dmesg 2>/dev/null | grep -o 'pogo_keyboard_recv :show_buf  len:\[31\]  [0-9a-f]*' | tail -n 1 |
        sed -n 's/.*f1a1a22f0b05020003\([0-9a-f]\{12\}\).*/\1/p' |
        _awk '{ for (i = 11; i >= 1; i -= 2) printf "%s%s", toupper(substr($0, i, 2)), (i > 1 ? ":" : ""); print "" }'
}

mac_from_bt_config() {
    [ -f "$BT_CONFIG" ] || return
    _found=$(_awk -v vid="$KBD_VID" -v pid="$KBD_PID" '
        /^\[/ { s = substr($0, 2, 17); v = 0; p = 0 }
        $1 == "HogpVendorId" && $3 == vid { v = 1 }
        $1 == "HogpProductId" && $3 == pid { p = 1 }
        v && p { print toupper(s); v = 0 }' "$BT_CONFIG" | sort -u)
    # Only if exactly one keyboard is paired; with several, the pogo frame or the override decides
    [ "$(echo "$_found" | grep -c .)" = 1 ] && echo "$_found"
}

resolve_kbd_mac() {
    KBD_MAC_SOURCE=config
    valid_mac "$KBD_MAC" && return 0
    _m=$(cat "$MAC_OVERRIDE_FILE" 2>/dev/null | tr -d ' \r\n')
    if valid_mac "$_m"; then KBD_MAC=$(echo "$_m" | tr 'a-f' 'A-F'); KBD_MAC_SOURCE=override; return 0; fi
    _m=$(mac_from_pogo)
    if valid_mac "$_m"; then
        KBD_MAC=$_m; KBD_MAC_SOURCE=pogo
        if [ "$(cat "$MAC_DETECTED_FILE" 2>/dev/null)" != "$_m" ]; then
            mkdir -p "${MAC_DETECTED_FILE%/*}" && echo "$_m" > "$MAC_DETECTED_FILE"
            log "keyboard address detected from the pogo connection"
        fi
        return 0
    fi
    _m=$(cat "$MAC_DETECTED_FILE" 2>/dev/null)
    if valid_mac "$_m"; then KBD_MAC=$_m; KBD_MAC_SOURCE=detected; return 0; fi
    _m=$(mac_from_bt_config)
    if valid_mac "$_m"; then KBD_MAC=$_m; KBD_MAC_SOURCE=paired; return 0; fi
    KBD_MAC=; KBD_MAC_SOURCE=none
    return 1
}

log() {
    if [ -f "$LOG_FILE" ] && [ "$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)" -gt "$LOG_MAX_BYTES" ]; then
        mv -f "$LOG_FILE" "$LOG_FILE.1"
    fi
    echo "$(date '+%m-%d %H:%M:%S') [${LOG_TAG:-pad2kbd}] $*" >> "$LOG_FILE"
    /system/bin/log -t pad2kbd "$*" 2>/dev/null
}

# Runs HidCtl as root via app_process; output goes to the log.
# app_process needs ART from /apex. Processes forked from KernelSU's post-fs-data stage
# (e.g. the uninstall cleanup) stay in the early bootstrap mount namespace without it and
# crash with SIGSEGV, so always run inside init's namespace.
hidctl() {
    _out=$(nsenter -t 1 -m -- env CLASSPATH="$MODDIR/hidctl.jar" app_process /system/bin \
        local.pad2kbd.pogopair.HidCtl "$@" 2>&1)
    _rc=$?
    log "hidctl $*: rc=$_rc $(echo "$_out" | tr '\n' ' ' | cut -c1-300)"
    return $_rc
}

# Installs an APK as a normal app and prints pm's output. pm hands its stdin and output to
# system_server, so neither may be a pipe (system_server keeps it open while an install waits, and
# $(...) never returns) nor a file under /data/adb (system_server may not use those fds: "Failed
# transaction"). The timeout keeps a stuck install from blocking the rest of the boot script.
install_apk() {
    _out=/data/local/tmp/pad2-pm-$$.out
    timeout 120 pm install -r -g "$1" </dev/null > "$_out" 2>&1
    cat "$_out" 2>/dev/null
    rm -f "$_out"
}

# 0 = attached, 1 = detached, 2 = unknown (input service unavailable, e.g. during shutdown)
pogo_state() {
    _in=$(dumpsys input 2>/dev/null)
    [ -n "$_in" ] || return 2
    echo "$_in" | grep -q "$POGO_INPUT_NAME"
}

is_attached() {
    pogo_state
}

# Android 17 init consumes sys.powerctl without storing it, and "adb reboot" bypasses the
# framework (no sys.shutdown.requested). init does write the reason to persist.sys.boot.reason
# (empty at runtime; bootstat clears it at boot) and stops zygote, so check those too.
shutting_down() {
    [ -n "$(getprop sys.shutdown.requested)$(getprop sys.powerctl)$(getprop persist.sys.boot.reason)" ] && return 0
    [ "$(getprop init.svc.zygote)" != "running" ]
}

resolve_kbd_mac
