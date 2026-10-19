#!/system/bin/sh
# Pad 2 keyboard — Bluetooth bond diagnostic. READ-ONLY (dumpsys/getprop only).
# Explains the "Pairing request - Tap to pair with null" prompt: the module only asks Android to
# bond when the keyboard is NOT bonded, so that prompt means the bond hasn't completed. A working
# unit shows the keyboard in "Bonded devices" as an encrypted LE bond.
# Run in a ROOT shell:  sh /data/local/tmp/pad2kbd-bond-check.sh

LOG=${LOG:-/data/local/tmp/pad2kbd-bond-check.txt}
BTC=/data/misc/bluedroid/bt_config.conf
TMP=${TMP:-/data/local/tmp/pad2kbd-bt.dump}

mask() { sed -E 's/([0-9A-Fa-f]{2}:){4}([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2})/XX:XX:XX:XX:\2/g'; }

# Describe one bonded line (persists whether connected or not).
describe() {  # $1=label  $2=device-name-in-dumpsys
  label=$1; nm=$2
  line=$(grep -iF "$nm" "$TMP" 2>/dev/null | grep -F '=>' | head -1)
  if [ -z "$line" ]; then
    echo "$label: NOT in Bonded devices  (bond state = NONE)"
    return 1
  fi
  tr=$(echo "$line" | sed -n 's/.*=>[^[]*\[  *\([A-Z/]*\)  *\].*/\1/p' | head -1)
  case "$line" in *"LE:Y"*) conn="connected (LE)";; *) conn="not connected now";; esac
  case "$line" in *EncryptionStatus*) enc="encrypted";; *) enc="not encrypted now";; esac
  echo "$label: BONDED  transport=$tr  $conn  $enc"
  echo "$line" | mask | sed 's/^/    /'
  return 0
}

run() {
  echo "================ Pad 2 keyboard bond check ================"
  echo "when:    $(date)"
  echo "device:  $(getprop ro.product.device)  android $(getprop ro.build.version.release) (sdk $(getprop ro.build.version.sdk))"
  echo "module:  $(sed -n 's/^version=//p' /data/adb/modules/pad2_keyboard_ble/module.prop 2>/dev/null) (want 0.11)"
  echo

  # keyboard / stylo address from bt_config, for reference (by OnePlus vid + pid)
  KBD=$(awk '/^\[/{m=substr($0,2,17);v="";p=""} $1=="HogpVendorId"{v=$3} $1=="HogpProductId"{p=$3} $1=="HogpDescriptor"{if(v=="8921"&&p=="14441")print m}' "$BTC" 2>/dev/null | head -1)
  echo "keyboard address (bt_config): $(echo "${KBD:-<none>}" | mask)"
  echo

  dumpsys bluetooth_manager > "$TMP" 2>/dev/null
  echo "Bonded devices total: $(grep -i 'Bonded devices:' "$TMP" | grep -o '[0-9]*' | head -1)"
  echo
  describe "KEYBOARD (OnePlus Pad Smart Keyboard)" "OnePlus Pad Smart Keyboard"; kbok=$?
  echo
  describe "Stylo 2 (for context)"                 "OnePlus Stylo 2"
  echo

  kbline=$(grep -iF "OnePlus Pad Smart Keyboard" "$TMP" 2>/dev/null | grep -F '=>' | head -1)
  kbtr=$(echo "$kbline" | sed -n 's/.*=>[^[]*\[  *\([A-Z/]*\)  *\].*/\1/p' | head -1)
  case "$kbline" in *EncryptionStatus*) kbenc=yes;; *) kbenc=no;; esac
  echo "================ VERDICT ================"
  if [ "$kbok" -ne 0 ] || [ -z "$kbline" ]; then
    echo "The keyboard is NOT bonded (not in the Bonded devices list)."
    echo "This is exactly the 'Tap to pair with null' prompt: the module is asking Android to bond the"
    echo "keyboard and it hasn't completed."
    echo "  -> Tap PAIR & CONNECT on that notification (do NOT cancel). It's your own keyboard."
    echo "  -> Then wait ~30 s: a fresh bond makes Android re-cache the truncated 512-byte map, so the"
    echo "     module restarts Bluetooth once and re-applies the 563-byte fix. Then test the touchpad."
    echo "  -> If the prompt keeps returning on every detach, the bond isn't persisting on this build."
  elif [ "$kbtr" != "LE" ]; then
    echo "The keyboard is bonded over the WRONG transport ($kbtr, not LE)."
    echo "This happens after using 'Pair new device'. The touchpad/keys won't work right over Bluetooth."
    echo "  -> Forget the keyboard, turn Bluetooth off/on, then ATTACH and DETACH it and accept the"
    echo "     module's LE pairing prompt. Do NOT use 'Pair new device'."
  elif [ "$kbenc" = yes ]; then
    echo "The keyboard is a HEALTHY encrypted LE bond (same as a working unit)."
    echo "Bonding is NOT the problem. If the touchpad still fails over Bluetooth, go back to the"
    echo "touchpad getevent test; the issue is cursor/gesture handling on this Android build."
  else
    echo "The keyboard is bonded over LE but not encrypted/connected right now."
    echo "  -> Attach then detach it to wake the Bluetooth link, and re-run this check."
  fi
  echo "========================================="
  rm -f "$TMP"
}

run | tee "$LOG"
echo
echo "Full log saved to: $LOG   (paste it back in full)"
