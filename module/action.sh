#!/system/bin/sh
# KernelSU/Magisk "Action" button: re-apply the current mode and show status.

MODDIR=${0%/*}
LOG_TAG=action
. "$MODDIR/common.sh"

if is_attached; then NOW=attached; else NOW=detached; fi
case "$KBD_MAC_SOURCE" in
    config) SRCTXT="set in config.sh" ;;
    override) SRCTXT="pinned in $MAC_OVERRIDE_FILE" ;;
    pogo) SRCTXT="read from the attached keyboard" ;;
    detected) SRCTXT="last keyboard that was attached" ;;
    paired) SRCTXT="the paired OnePlus keyboard" ;;
    *) SRCTXT="unknown" ;;
esac
if [ -z "$KBD_MAC" ]; then
    echo "Keyboard address: not found yet. Attach the keyboard to the tablet once and press this"
    echo "button again, or pin it: echo AA:BB:CC:DD:EE:FF > $MAC_OVERRIDE_FILE"
    exit 0
fi
echo "Keyboard: $KBD_MAC ($SRCTXT)  pogo: $NOW"
echo "Another keyboard is picked up when it's attached. To pin one: echo AA:BB:CC:DD:EE:FF > $MAC_OVERRIDE_FILE"
SRC=action sh "$MODDIR/switch-mode.sh" "$NOW" force
if rom_native; then
    echo "Mode: ROM handles the keyboard ($ROM_KBD_PKG); the module only keeps the Bluetooth link fast"
    if rom_touchpad_resolution; then echo "Touchpad resolution: set by the ROM"
    else echo "Touchpad resolution: NOT set by the ROM (BLE pointer may be ~6x too fast)"; fi
else
    echo "Mode: full (pairing, HID switching, report map repair, latency)"
    sh "$MODDIR/descriptor-fix.sh" check
    case $? in
        0) echo "Report map: truncated (will be repaired on next Bluetooth restart/reboot)" ;;
        1) echo "Report map: OK or keyboard not bonded" ;;
        4) echo "Report map: truncated and repair INVALID - see log" ;;
    esac
fi
CLASSPATH="$MODDIR/hidctl.jar" app_process /system/bin local.pad2kbd.pogopair.HidCtl status "$KBD_MAC" 2>&1
echo "Log: $LOG_FILE"
tail -n 8 "$LOG_FILE" 2>/dev/null
