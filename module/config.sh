#!/system/bin/sh
# All device-specific values for the Pad 2 keyboard module live here.
# Every other script sources this file; nothing else hardcodes these values.

# --- keyboard identity (Pad 2 Smart Keyboard, collected 2026-10-13) ---
# The keyboard's Bluetooth address. Leave empty: the module finds it by itself (see
# resolve_kbd_mac in common.sh). To pin a specific keyboard without rebuilding the module, write its
# address to /data/adb/pad2kbd/keyboard_mac instead (survives module updates).
KBD_MAC=
KBD_VID=8921            # 0x22D9 OnePlus
KBD_PID=14441           # 0x3869

# --- HID report map repair ---
# Android reads 512 bytes of the 563-byte map over GATT; the remaining 51 bytes
# (end of the touchpad collection) are appended from here. Read from the keyboard itself
# over BlueZ on a Linux PC (2026-10-16), which fetches the whole map.
DESC_TRUNC_BYTES=512
DESC_FULL_BYTES=563
DESC_TAIL=0c66011047ffff000027ffff000075109501050d095681020954257f95017508810205090901250175019501810295078103c0
# Tails written by older module versions (v0.1-v0.10: 49 bytes inferred from the Pad 3).
# A map ending in one of these is upgraded to DESC_TAIL, and restore recognizes them.
DESC_OLD_TAILS=0c66011047ffff000027ffff000075109501095681020954250575089501810205091901290115002501750895018102c0
# Touchpad size fix: the firmware declares Physical Max = Logical Max (2764 x 1630 in 0.01 inch,
# i.e. 70 x 41 cm), so Android moves the BLE pointer ~6x too fast. These byte swaps (old:new, per
# finger slot) declare the real 4.73 x 2.79 in (120 x 71 mm) = 23 units/mm, same as pogo_touchpad.
# Set to empty to disable.
DESC_SWAPS="46cc0a:46d901 465e06:461701"

# --- ROMs that handle the keyboard themselves ---
# Some caihong ROMs ship OplusKeyboard (org.lineageos.keyboard, from hardware/oplus): it pairs the
# keyboard on detach and switches HID between pogo and Bluetooth by itself, the Bluetooth stack reads
# the whole 563-byte map, and the IDC file fixes the touchpad resolution. Then the module only keeps
# the Bluetooth link fast and leaves pairing, HID policy and the report map alone.
# auto = detect (the app's default-permissions file), yes/no = force. docs/ROM-NATIVE.md explains why.
ROM_KBD_PKG=org.lineageos.keyboard
ROM_NATIVE=auto

# --- attach/detach detection ---
UEVENT_DEVNAME=pogo_keyboard     # uevent DEVNAME of the pogo driver
UEVENT_STATUS_VAR=pogopin_status # 1 = attached, 0 = detached
POGO_INPUT_NAME=pogo_touchpad    # input device present only while attached
POLL_SECONDS=3

# --- environment ---
BT_CONFIG=/data/misc/bluedroid/bt_config.conf
STATE_DIR=/data/adb/pad2kbd      # backups and state (root only)
LOG_FILE=/data/local/tmp/pad2kbd.log
LOG_MAX_BYTES=262144
APP_PKG=local.pad2kbd.pogopair
MAX_BT_RESTARTS_PER_BOOT=3

# Global hidden-API exemption (hidden_api_policy*=1). Off by default: the companion
# app is a priv-app and HidCtl runs under app_process, so it should not be needed.
# Set to 1 only if testing proves otherwise; uninstall restores the old values.
HIDDEN_API_POLICY=0

# busybox: first one found wins (KernelSU, Magisk, APatch)
for _bb in /data/adb/ksu/bin/busybox /data/adb/magisk/busybox /data/adb/ap/bin/busybox; do
    [ -x "$_bb" ] && { BB=$_bb; break; }
done
unset _bb
