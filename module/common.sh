#!/system/bin/sh
# Shared helpers. Caller sets MODDIR before sourcing.

. "$MODDIR/config.sh"

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
