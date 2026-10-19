#!/system/bin/sh
# Pad 2 keyboard — BLE touchpad diagnostic. READ-ONLY (getprop/getevent/dumpsys only).
# Run in a ROOT shell with the keyboard DETACHED (on Bluetooth, not on the pins):
#     sh /data/local/tmp/pad2kbd-touchpad-test.sh
# It records an 8 s window; swipe the touchpad when it says SWIPE NOW.

SECS=${SECS:-8}
LOG=${LOG:-/data/local/tmp/pad2kbd-touchpad-test.txt}

run() {
  echo "================ Pad 2 keyboard touchpad test ================"
  echo "when:    $(date)"
  echo "device:  $(getprop ro.product.device)  android $(getprop ro.build.version.release) (sdk $(getprop ro.build.version.sdk))"
  echo "module:  $(sed -n 's/^version=//p' /data/adb/modules/pad2_keyboard_ble/module.prop 2>/dev/null) (want 0.11)"
  echo

  # Locate the BLE touchpad node and the pogo touchpad node by input-device name.
  BLE=""; POGO=""
  for e in /dev/input/event*; do
    info=$(getevent -lp "$e" 2>/dev/null)
    case "$info" in
      *"Smart Keyboard Touchpad"*) BLE="$e" ;;
      *"pogo_touchpad"*)           POGO="$e" ;;
    esac
  done
  echo "BLE touchpad node (over Bluetooth): ${BLE:-<none present>}"
  echo "pogo touchpad node (on the pins):   ${POGO:-<none present>}"
  echo

  if [ -n "$POGO" ] && [ -z "$BLE" ]; then
    echo "RESULT: keyboard is DOCKED (pogo node present, no BLE node)."
    echo "        The module suspends Bluetooth HID while docked, so this test can't run."
    echo "        DETACH the keyboard (use it over Bluetooth) and run the script again."
    return 0
  fi
  if [ -z "$BLE" ]; then
    echo "RESULT: no touchpad node found at all. Is the keyboard connected?"
    echo "        Detach it so it's on Bluetooth, make sure keys work, then run again."
    return 0
  fi

  # Touchpad configuration Android derived from the (repaired) descriptor.
  echo "--- Touchpad Input Mapper (working baseline: resolution=23, Stack Version 2) ---"
  dumpsys input 2>/dev/null | grep -A20 'Touchpad Input Mapper' \
    | grep -E 'resolution=|Device Touchpad|Stack Version' | head -6
  echo

  # Timed capture to a FILE (not a shell variable: a working touchpad floods thousands of
  # lines and would overflow ARG_MAX). getevent is killed by timeout after $SECS; no Ctrl-C.
  CAP=${CAP:-/data/local/tmp/pad2kbd-touchpad.cap}
  echo ">>> Get ready. In 3 seconds, SWIPE the touchpad continuously until it says STOP."
  sleep 3
  echo "############################## SWIPE NOW (${SECS}s) ##############################"
  timeout "$SECS" getevent -lt "$BLE" > "$CAP" 2>/dev/null
  echo "################################## STOP #########################################"
  echo

  total=$(grep -c .                         "$CAP" 2>/dev/null); total=${total:-0}
  abs=$(grep -c   'ABS_MT_POSITION'         "$CAP" 2>/dev/null); abs=${abs:-0}
  btn=$(grep -cE  'BTN_TOUCH|BTN_TOOL_FINGER' "$CAP" 2>/dev/null); btn=${btn:-0}
  echo "events captured on the BLE touchpad while you swiped:"
  echo "    total lines         = $total"
  echo "    ABS_MT_POSITION_*    = $abs"
  echo "    BTN_TOUCH/TOOL       = $btn"
  echo
  echo "--- sample (first 8 motion lines) ---"
  grep -E 'ABS_MT|BTN_|EV_SYN' "$CAP" 2>/dev/null | head -8
  rm -f "$CAP"
  echo

  if [ "$abs" -gt 0 ] || [ "$btn" -gt 0 ]; then
    echo "VERDICT: the BLE touchpad IS sending data (touch events seen)."
    echo "         The report reaches Android; the cursor/gesture step is what's missing on this"
    echo "         Android build. Not fixable from the module — the pogo path works because it's a"
    echo "         separate kernel driver."
  else
    echo "VERDICT: the BLE touchpad sent NOTHING while you swiped."
    echo "         The node and descriptor are correct but no touch reports arrive over Bluetooth."
    echo "         Try a clean re-pair (forget; Bluetooth off/on; attach then detach; accept the"
    echo "         pairing prompt; NOT 'Pair new device'), then run this again BEFORE docking."
  fi
  echo "=============================================================="
}

run | tee "$LOG"
echo
echo "Full log saved to: $LOG   (paste it back in full)"
