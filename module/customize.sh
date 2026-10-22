#!/system/bin/sh
# Install-time checks (sourced by the KernelSU/Magisk installer).

DEV="$(getprop ro.custom.device) $(getprop ro.product.vendor.device) $(getprop ro.product.device)"
case "$DEV" in
    *caihong*|*OP5DAAL1*) ui_print "- Device: OnePlus Pad 2 ($DEV)" ;;
    *) abort "! This module is only for the OnePlus Pad 2 (caihong); found: $DEV" ;;
esac

if [ -d /data/adb/modules/oneplus_pogo_keyboard_ble ] && [ ! -f /data/adb/modules/oneplus_pogo_keyboard_ble/remove ]; then
    ui_print "! WARNING: the Pad 3 module (oneplus_pogo_keyboard_ble) is still installed."
    ui_print "!          Remove it before rebooting so the two do not fight over Bluetooth."
fi

for d in /system_ext /product /system /vendor /odm; do
    if [ -f "$d/etc/default-permissions/default-permissions_org.lineageos.keyboard.xml" ]; then
        ui_print "- This ROM handles the keyboard over Bluetooth itself (OplusKeyboard):"
        ui_print "  the module will only keep the Bluetooth link fast for the touchpad."
        break
    fi
done

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in post-fs-data.sh service.sh uninstall.sh action.sh switch-mode.sh \
         uevent-handler.sh descriptor-fix.sh config.sh common.sh; do
    set_perm "$MODPATH/$f" 0 0 0755
done
ui_print "- Log file: /data/local/tmp/pad2kbd.log"
ui_print "- The keyboard's address is found automatically: attach the keyboard once."
ui_print "  To pin a specific keyboard: echo AA:BB:CC:DD:EE:FF > /data/adb/pad2kbd/keyboard_mac"
