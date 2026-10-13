#!/system/bin/sh
# Called by "busybox uevent" for every kernel uevent (variables arrive in the environment).

MODDIR=${0%/*}
. "$MODDIR/config.sh"

[ "$DEVNAME" = "$UEVENT_DEVNAME" ] || exit 0

eval "STATUS=\$$UEVENT_STATUS_VAR"
case "$STATUS" in
    0) SRC=uevent sh "$MODDIR/switch-mode.sh" detached ;;
    1) SRC=uevent sh "$MODDIR/switch-mode.sh" attached ;;
esac
