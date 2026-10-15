# Changelog

## 0.10
- **Fix:** with both Pad 2 modules installed at once, only one app got installed. Android may ask
  you to allow each app's install but shows one such prompt at a time, so the second install waited
  for good. The two modules now take turns, each install gets 5 minutes, and the time limit now
  stops the install itself. Whether the app is installed is checked by comparing the installed APK
  with the module's, so an install you allow late is recognised at the next boot.

## 0.9
- **Fix:** after installing the module (e.g. removing and reinstalling it), the boot script could
  hang on the app install, and attaching and detaching stopped working. `pm` hands its input and output to
  Android's system service: a pipe stays open while an install waits, so the script waited for good,
  and a file under `/data/adb` is refused ("Failed transaction"). pm now reads from `/dev/null` and
  writes to a file in `/data/local/tmp`, with a 2-minute limit, and the app is only recorded as
  installed when it worked, so the next boot tries again otherwise. The uevent listener now starts
  before the install, so attach/detach work even if it fails.
- The installer shows the author ("by ardy"; the apostrophe in the old author line hid it), and the
  module is called "OnePlus Pad 2 Keyboard BLE".

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
