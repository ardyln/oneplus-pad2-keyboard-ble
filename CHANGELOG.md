# Changelog

## 0.12
- **ROMs that handle the keyboard themselves:** if the ROM ships `OplusKeyboard`
  (`org.lineageos.keyboard`, e.g. inferno0230's PixelOS 17 builds from 2026-10-22), the module
  only keeps the Bluetooth link fast. It no longer edits the report map (at boot or at uninstall),
  restarts Bluetooth, pairs the keyboard or switches the HID policy there (uninstalling doesn't
  either); the ROM does that.
  `ROM_NATIVE` in `config.sh` can force either mode. The Action button shows the mode, and whether
  the ROM sets the touchpad resolution. Details: `docs/ROM-NATIVE.md`.
- **Touchpad latency: the keyboard's own 7.5 ms on every detach.** Android applies the keyboard's
  preferred connection parameters (7.5 ms) only at pairing and forgets them at reboot, so the link
  fell back to 45 ms (an AOSP behaviour, see `docs/ROM-NATIVE.md`). On each detach the root helper
  (`HidCtl tune`) now reads those parameters from the keyboard and applies them the way Android
  does at pairing. The app's high-priority request (11.25-15 ms) is now only the fallback, and only
  when the link is slower than 15 ms, so it no longer slows down a faster link.
- **Fix:** on a fresh install, Android blocked the latency helper from starting in the background
  until the next reboot. The module whitelisted the app before installing it.
- New: `tools/btsnoop_kbd.py`, which reads an HCI snoop log: connection-interval timeline, how the
  touchpad's reports arrive, and attribute reads (report map, preferred parameters).

## 0.11
- **Fix:** the last 51 bytes of the keyboard's HID report map (the end of the touchpad description)
  are now the real ones, read from the keyboard over Bluetooth on a Linux PC. Earlier versions used
  49 bytes inferred from the Pad 3. A map already repaired by an older version is upgraded at the
  next boot, and restoring the original map recognises both.
- New: `linux/61-oneplus-pad-keyboard.hwdb` for using the keyboard with a Linux PC (touchpad
  speed, Esc, Search and microphone keys).
- README: how to get the keyboard back after pairing it with another device (removing it there is
  needed; blocking it isn't enough).

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
