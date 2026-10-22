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

# Gives the keyboard its own preferred BLE parameters (7.5 ms) in the background, one run at a
# time; "HidCtl tune" waits for the pairing and the connection itself (docs/ROM-NATIVE.md).
tune_link() {
    mkdir "$STATE_DIR/tune.lock" 2>/dev/null || { log "tune already running"; return 0; }
    ( hidctl tune "$KBD_MAC"; rmdir "$STATE_DIR/tune.lock" ) </dev/null >/dev/null 2>&1 &
}

stop_tune() {
    pkill -f 'pogopair.HidCtl tune' 2>/dev/null
    rmdir "$STATE_DIR/tune.lock" 2>/dev/null
}

# Installs an APK as a normal app and prints the install's output.
# - Android may ask the user to allow the install and shows one such prompt at a time, so the Pad 2
#   modules take turns (a lock shared by both), and each install gets 5 minutes.
# - cmd package (what /system/bin/pm wraps) is called directly, so the time limit stops the install
#   itself, not just the wrapper.
# - Its stdin and output are neither a pipe nor a file under /data/adb: system_server keeps a pipe
#   open while an install waits, and refuses fds of /data/adb files ("Failed transaction").
INSTALL_LOCK=/dev/pad2-install.lock
install_apk() {
    _out=/data/local/tmp/pad2-pm-$$.out
    _i=0
    until mkdir "$INSTALL_LOCK" 2>/dev/null; do
        _i=$((_i + 1)); [ $_i -ge 1200 ] && break   # give up waiting after 20 minutes
        sleep 1
    done
    timeout 300 cmd package install -r -g "$1" </dev/null > "$_out" 2>&1
    rmdir "$INSTALL_LOCK" 2>/dev/null
    cat "$_out" 2>/dev/null
    rm -f "$_out"
}

# True when the installed app $1 is exactly the APK with sha256 $2 (Android keeps the file as is),
# so an install that was allowed late or finished after the time limit counts at the next boot.
app_current() {
    _p=$(pm path "$1" </dev/null 2>/dev/null | head -n 1)
    _p=${_p#package:}
    [ -n "$_p" ] && [ "$(sha256sum "$_p" 2>/dev/null | cut -d' ' -f1)" = "$2" ]
}

# True when the ROM handles the keyboard over Bluetooth itself (see config.sh). Uses the app's
# default-permissions file, so it also works in post-fs-data, before the package manager runs.
rom_native() {
    case "$ROM_NATIVE" in
        yes) return 0 ;;
        no) return 1 ;;
    esac
    for _d in /system_ext /product /system /vendor /odm; do
        [ -f "$_d/etc/default-permissions/default-permissions_$ROM_KBD_PKG.xml" ] && return 0
    done
    return 1
}

# True when the IDC file sets the touchpad resolution (ROM-side fix for the 4 units/mm map).
rom_touchpad_resolution() {
    _idc=$(printf 'Vendor_%04x_Product_%04x.idc' "$KBD_VID" "$KBD_PID")
    grep -qs '^[[:space:]]*touchpad\.resolution\.x' "/odm/usr/idc/$_idc" "/vendor/usr/idc/$_idc" \
        "/system/usr/idc/$_idc"
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
