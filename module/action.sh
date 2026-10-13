#!/system/bin/sh
# KernelSU/Magisk "Action" button: re-apply the current mode and show status.

MODDIR=${0%/*}
LOG_TAG=action
. "$MODDIR/common.sh"

if is_attached; then NOW=attached; else NOW=detached; fi
echo "Keyboard: $KBD_MAC  pogo: $NOW"
SRC=action sh "$MODDIR/switch-mode.sh" "$NOW" force
sh "$MODDIR/descriptor-fix.sh" check
case $? in
    0) echo "Report map: truncated (will be repaired on next Bluetooth restart/reboot)" ;;
    1) echo "Report map: OK or keyboard not bonded" ;;
    4) echo "Report map: truncated and repair INVALID - see log" ;;
esac
CLASSPATH="$MODDIR/hidctl.jar" app_process /system/bin local.pad2kbd.pogopair.HidCtl status "$KBD_MAC" 2>&1
echo "Log: $LOG_FILE"
tail -n 8 "$LOG_FILE" 2>/dev/null
