# Changelog

## 0.8
- The keyboard's Bluetooth address is found automatically: from the pogo connection while the
  keyboard is attached, else the last keyboard found that way, else the only paired OnePlus keyboard.
  A different keyboard is picked up when it's attached; one keyboard can be pinned in
  `/data/adb/pad2kbd/keyboard_mac` without rebuilding. `KBD_MAC` in `config.sh` is empty by default.
- The Action button shows the address in use and where it came from.
- Module updates through KernelSU (`updateJson`; Magisk untested).

## 0.7
- First public version: Bluetooth fallback for the Pad 2 Smart Keyboard when it's detached (HID report
  map repair, touchpad size fix, no double input while attached, low-latency connection).
