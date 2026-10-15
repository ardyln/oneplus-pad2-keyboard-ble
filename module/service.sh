#!/system/bin/sh

MODDIR=${0%/*}
LOG_TAG=service
. "$MODDIR/common.sh"

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
until [ "$(getprop sys.user.0.ce_available)" = "true" ]; do sleep 2; done

# Lets the latency helper start from a background broadcast. Undone by uninstall.sh.
cmd deviceidle whitelist +"$APP_PKG" >/dev/null 2>&1

if [ "$HIDDEN_API_POLICY" = "1" ]; then
    if [ ! -f "$STATE_DIR/hidden_api_policy.orig" ]; then
        for k in hidden_api_policy hidden_api_policy_p_apps hidden_api_policy_pre_p_apps; do
            echo "$k=$(settings get global $k)"
        done > "$STATE_DIR/hidden_api_policy.orig"
    fi
    for k in hidden_api_policy hidden_api_policy_p_apps hidden_api_policy_pre_p_apps; do
        settings put global $k 1 >/dev/null 2>&1
    done
    log "hidden_api_policy* set to 1 (previous values in $STATE_DIR/hidden_api_policy.orig)"
fi

if [ -n "$BB" ]; then
    "$BB" uevent "$MODDIR/uevent-handler.sh" &
    log "uevent listener started (pid $!)"
else
    log "no busybox: relying on the $POLL_SECONDS s poll only"
fi

# KernelSU without a mounting metamodule does not overlay system/, so the priv-app copy is
# never seen. Fall back to installing the APK as a normal app (removed again by uninstall.sh).
# This runs after the uevent listener has started, so attach/detach work even if it fails.
mkdir -p "$STATE_DIR"
APK="$MODDIR/system/priv-app/Pad2KbdPair/Pad2KbdPair.apk"
if ! pm path "$APP_PKG" 2>/dev/null | grep -q "^package:/system"; then
    want=$(sha256sum "$APK" | cut -d' ' -f1)
    if ! app_current "$APP_PKG" "$want"; then
        # The package manager can't read files under /data/adb; stage a copy it can read.
        cp -f "$APK" /data/local/tmp/pad2kbd.apk && chmod 0644 /data/local/tmp/pad2kbd.apk
        out=$(install_apk /data/local/tmp/pad2kbd.apk)
        rm -f /data/local/tmp/pad2kbd.apk
        log "installed $APP_PKG as a normal app: ${out:-no answer within 5 minutes}"
    fi
    # Remembered for uninstall.sh, which removes the app only if this module installed it
    app_current "$APP_PKG" "$want" && touch "$STATE_DIR/app_user_installed"
fi

# Poll loop: fallback attach/detach detection, plus repair of the report map after a new bond.
# A new bond stores the 512-byte map; repairing needs the stack stopped, so Bluetooth is
# restarted once, then the detached path re-allows HID (the stack forbids it after a failed probe).
LAST=""
while true; do
    pogo_state; st=$?
    if shutting_down || [ $st -eq 2 ]; then sleep "$POLL_SECONDS"; continue; fi
    if [ $st -eq 0 ]; then NOW=attached; else NOW=detached; fi
    if [ "$NOW" != "$LAST" ]; then
        SRC=poll sh "$MODDIR/switch-mode.sh" "$NOW"
        LAST=$NOW
    fi

    sh "$MODDIR/descriptor-fix.sh" check
    if [ $? -eq 0 ]; then
        n=$(cat "$STATE_DIR/bt_restarts" 2>/dev/null || echo 0)
        if [ "$n" -ge "$MAX_BT_RESTARTS_PER_BOOT" ]; then
            [ "$n" -eq "$MAX_BT_RESTARTS_PER_BOOT" ] && log "restart limit reached; not restarting Bluetooth again this boot"
            echo $((n + 1)) > "$STATE_DIR/bt_restarts"
        else
            echo $((n + 1)) > "$STATE_DIR/bt_restarts"
            log "new bond with truncated map: restarting Bluetooth to repair it ($((n + 1))/$MAX_BT_RESTARTS_PER_BOOT)"
            cmd bluetooth_manager disable >/dev/null 2>&1
            cmd bluetooth_manager wait-for-state:STATE_OFF >/dev/null 2>&1
            sh "$MODDIR/descriptor-fix.sh" apply
            cmd bluetooth_manager enable >/dev/null 2>&1
            cmd bluetooth_manager wait-for-state:STATE_ON >/dev/null 2>&1
            sleep 2
            if is_attached; then NOW=attached; else NOW=detached; fi
            SRC=bt-restart sh "$MODDIR/switch-mode.sh" "$NOW" force
            LAST=$NOW
        fi
    fi
    sleep "$POLL_SECONDS"
done
