#!/system/bin/sh
# Runs at the start of the boot after the module is marked for removal (Bluetooth not running yet).
# Undoes every persistent change: report map edit, HID policy, deviceidle whitelist,
# hidden-API settings (only if this module changed them), and the state directory.

MODDIR=${0%/*}
LOG_TAG=uninstall
. "$MODDIR/common.sh"

log "uninstalling"
sh "$MODDIR/descriptor-fix.sh" restore

# The module directory is deleted right after this script returns, so the late cleanup
# runs from a copy of what it needs.
WORK="$STATE_DIR/uninstall"
mkdir -p "$WORK"
cp -f "$MODDIR/hidctl.jar" "$MODDIR/config.sh" "$MODDIR/common.sh" "$WORK/"

(
    MODDIR=$WORK
    . "$WORK/common.sh"
    LOG_TAG=uninstall
    until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
    sleep 10
    cmd deviceidle whitelist -"$APP_PKG" >/dev/null 2>&1
    if [ -f "$STATE_DIR/app_user_installed" ]; then
        log "removing $APP_PKG: $(pm uninstall "$APP_PKG" 2>&1)"
    fi
    if [ -f "$STATE_DIR/hidden_api_policy.orig" ]; then
        while IFS='=' read -r k v; do
            if [ "$v" = "null" ] || [ -z "$v" ]; then settings delete global "$k" >/dev/null 2>&1
            else settings put global "$k" "$v" >/dev/null 2>&1; fi
        done < "$STATE_DIR/hidden_api_policy.orig"
        log "hidden_api_policy* restored"
    fi
    # Leave the keyboard's HID policy at the Android default (allowed), never stuck at forbidden.
    hidctl allow "$KBD_MAC"
    log "uninstall complete; removing $STATE_DIR (bt_config backup included)"
    rm -rf "$STATE_DIR"
) </dev/null >/dev/null 2>&1 &
