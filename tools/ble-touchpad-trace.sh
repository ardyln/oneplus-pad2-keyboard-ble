#!/system/bin/sh
# Capture + check the HCI proof for the "touchpad doesn't work over Bluetooth" bug (docs/BLE-TOUCHPAD.md).
# Over Bluetooth the host enables each HID report's notifications (a CCCD write) at BOND time; keys
# work but the touchpad doesn't when the touchpad report's CCCD (0x0034) is never written. This finds
# out, on-device, no PC needed -- and saves the full logs for a bug report.
#
# Run in a ROOT shell, three steps:
#   sh ble-touchpad-trace.sh arm     # start a clean capture, prints what to do on screen
#   ...do the on-screen forget + re-pair...
#   sh ble-touchpad-trace.sh grab    # scan + verdict + save the logs
#   sh ble-touchpad-trace.sh off     # stop capturing
#
# READ-ONLY except: it toggles the HCI snoop setting, restarts Bluetooth, and writes the saved
# logs to /sdcard. It changes nothing about the keyboard or the module.

LOGDIR=/data/misc/bluetooth/logs
OUT=${OUT:-/sdcard}

# Prints the ATT handles that received a CCCD-enable write (ATT opcode 0x12/0x52, value 0100) in a
# btsnoop file. Byte-level heuristic (no btmon on Android); the saved logs are the authoritative copy.
hexscan() {
    [ -f "$1" ] || return
    od -An -v -tx1 "$1" 2>/dev/null | tr -d ' \n' \
        | grep -oE '(12|52)[0-9a-f]{4}0100' \
        | sed -E 's/^(12|52)([0-9a-f]{2})([0-9a-f]{2})0100$/0x\3\2/' | sort -u
}

case "$1" in
arm)
    setprop persist.bluetooth.btsnooplogmode full
    cmd bluetooth_manager disable >/dev/null 2>&1
    cmd bluetooth_manager wait-for-state:STATE_OFF >/dev/null 2>&1
    rm -f "$LOGDIR"/btsnoop_hci.log*
    cmd bluetooth_manager enable >/dev/null 2>&1
    cmd bluetooth_manager wait-for-state:STATE_ON >/dev/null 2>&1
    [ -f "$LOGDIR/btsnoop_hci.log" ] && echo "ARMED (clean full HCI capture running)." \
        || echo "ARMED, but no snoop log appeared yet -- check 'getprop persist.bluetooth.btsnooplogmode' = full."
    echo
    echo "NOW, on the tablet SCREEN (this produces no terminal output):"
    echo "  1. Settings -> Bluetooth -> 'OnePlus Pad Smart Keyboard' -> Forget"
    echo "  2. Attach the keyboard to the pins, wait ~3 s, then detach it"
    echo "  3. Accept the pairing prompt (it may say 'pair with null')"
    echo "  4. Press ONE or TWO keys to confirm it works, then STOP"
    echo "     (typing a lot rotates the pairing out of the log)"
    echo
    echo "Then run:  sh $0 grab"
    ;;
grab)
    handles=$(printf '%s\n' "$(hexscan "$LOGDIR/btsnoop_hci.log.last")" "$(hexscan "$LOGDIR/btsnoop_hci.log")" | sort -u | grep .)
    has() { printf '%s\n' "$handles" | grep -qx "$1"; }
    has 0x0029 && kb=yes || kb=NO
    has 0x002d && co=yes || co=NO
    has 0x0034 && tp=yes || tp=NO
    echo "================ touchpad CCCD check ================"
    echo "keyboard report CCCD 0x0029 (keys)     : $kb"
    echo "keyboard report CCCD 0x002d (consumer) : $co"
    echo "TOUCHPAD  report CCCD 0x0034           : $tp"
    echo "----------------------------------------------------"
    if [ "$tp" = yes ]; then
        echo "VERDICT: the touchpad CCCD WAS enabled at bond -- the keyboard is told to send the touchpad."
        echo "         If the touchpad works, all good. If it still does NOT, the fault is downstream (the"
        echo "         report isn't routed to the input device), not the CCCD -- note that in the report."
    elif [ "$kb" = yes ] || [ "$co" = yes ]; then
        echo "VERDICT: keyboard CCCD(s) enabled but the TOUCHPAD CCCD (0x0034) was NOT -> the Bluetooth"
        echo "         stack skips the touchpad's notification at bond. THIS IS THE BUG. Attach the saved"
        echo "         logs to a bug report (docs/BLE-TOUCHPAD.md)."
    else
        echo "VERDICT: no keyboard report CCCD writes found -> the capture likely missed the pairing."
        echo "         Re-run: sh $0 arm, do the forget+re-pair, press only a key or two, then grab."
    fi
    echo "all CCCD-enabled handles seen (incl. other devices): $(printf '%s ' $handles)"
    echo "===================================================="
    echo
    for f in btsnoop_hci.log.last btsnoop_hci.log; do
        if [ -s "$LOGDIR/$f" ]; then
            gzip -c "$LOGDIR/$f" | base64 > "$OUT/$f.gz.b64"
            echo "saved: $OUT/$f.gz.b64 ($(wc -c < "$OUT/$f.gz.b64") bytes)"
        fi
    done
    echo "Attach the saved file(s) to the bug report. (Decode with: base64 -d FILE | gunzip > x.btsnoop; btmon -r x.btsnoop)"
    ;;
off)
    setprop persist.bluetooth.btsnooplogmode disabled
    cmd bluetooth_manager disable >/dev/null 2>&1
    cmd bluetooth_manager enable >/dev/null 2>&1
    echo "HCI snoop disabled, Bluetooth restarted."
    ;;
*)
    echo "usage: sh $0 arm|grab|off   (run as root; see docs/BLE-TOUCHPAD.md)"
    exit 2
    ;;
esac
