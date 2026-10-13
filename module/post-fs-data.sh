#!/system/bin/sh
# Runs before the Bluetooth stack starts, so bt_config.conf can be edited safely.

MODDIR=${0%/*}
LOG_TAG=post-fs
. "$MODDIR/common.sh"

mkdir -p "$STATE_DIR"; chmod 0700 "$STATE_DIR"
rm -f "$STATE_DIR/mode" "$STATE_DIR/bt_restarts"
rmdir "$STATE_DIR/switch.lock" 2>/dev/null
log "boot: module $(grep '^version=' "$MODDIR/module.prop" | cut -d= -f2), busybox=${BB:-none}"
sh "$MODDIR/descriptor-fix.sh" apply
