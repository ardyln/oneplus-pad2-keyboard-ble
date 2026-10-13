# OnePlus Stylo 2: thumb button and haptics (research in progress)

Status as of 2026-10-13: **paused after passive investigation.** Nothing has been written to the pen
except standard CCC (notification enable/disable) descriptors, and those were all switched back off.

Goal: make the Stylo 2's capacitive **thumb button** and its **textured vibration** (haptics while
writing) work on AOSP ROMs (PixelOS 17 / LineageOS 24 on `caihong`), as they do on OxygenOS, where
the official pen app could configure them.

## What already works on AOSP
- Pen input through the screen digitizer (`touchpanel_pen`): X/Y, pressure, tilt, hover distance.
- BLE bond + HID profile (the pen exposes a mouse report and a keyboard report, VID 8921 / PID 14442).
- LineageOS's `org.lineageos.pen` (`android_hardware_oplus/packages/Pen`): pairing notification on
  magnetic attach (uevent `DEVPATH=/devices/virtual/oplus_wireless/pencil`, `pencil_status`,
  `pencil_addr`), refresh-rate cap, and a GATT relay of pressure to the touch HAL. Its relay looks
  for service `0783b03e-…`, which **this pen doesn't have**, so the relay never engages with the Stylo 2.

## Findings
The capacitive button produces **no input events** (checked with `getevent`, pen off the charger).
It is reported only over a vendor GATT characteristic that nothing on AOSP subscribes to.

| Service / characteristic | Props | Meaning (observed) |
|---|---|---|
| `18093398-2a69-11ec-8d3d-0242ac130003` / **`180938ac-…`** | notify | **Thumb button**: `01` per touch. No gesture distinction (tap/double/long/slide all `01`), at most ~1 event / 0.75 s, doesn't wake a sleeping pen |
| `18093398-…` / `1809396a-…` | notify | Charging state: `20` off charger, `21` charging (with `chg evt …` on the console) |
| `18093398-…` / `180937bc-…` | notify | Battery level (`64` = 100 %) |
| `18093398-…` / `180932da-…` | notify | not seen yet |
| `18092dbc-…` / `18093046-…` | write, notify | Pencil status `2c900101` + `00` idle / `01` active (LineageOS already decodes/acks this) |
| `18092dbc-…` / `1809314a-…`, `18093212-…` | read | read `64` and `21` (meaning unknown) |
| `6e400001-b5a3-f393-e0a9-e50e24dcca9e` (Nordic UART) / `6e400003` | notify | **Firmware debug console**, plain text: `sleep enter/exit`, `film 24` (thumb touch), `chg evt …`, `rx <hex> …` stats every 5 s while awake |
| NUS / `6e400004` | notify | not seen yet |
| NUS / `6e400002` | write | console input? **Do not write blindly** |
| `a6ed0401-d344-460a-8075-b9e8ec90d71b` / `a6ed0402` notify, `a6ed0403` write, `a6ed0404` write+indicate | | Unknown data/command channel. Candidate for haptics and pressure |
| `58480000-5a6a-1122-3300-004095112200` / `58480001` | write, notify | Unknown; possibly firmware update (**don't touch**) |

The full GATT table came from the tablet's cache `/data/misc/bluetooth/gatt_cache_<penaddr>`, decoded
with `tools/gatt_cache_dump.py`.

## Tools
- `tools/gatt_cache_dump.py FILE`: decodes an Android `gatt_cache_*` file into services and characteristics.
- `tools/penprobe/`: a debug app (`local.penprobe`). It subscribes to every vendor notify/indicate
  characteristic, reads the readable ones (it never reads the standard Serial Number characteristic),
  and logs everything to the screen and to logcat tag `PenProbe`. Its only writes are CCC descriptors.
  ```
  # build like the module app (javac -> d8 -> aapt2 -> zipalign -> apksigner), then:
  adb install -r PenProbe.apk
  adb shell su -c 'am start -n local.penprobe/.ProbeActivity --es mac <PEN_MAC>'                  # probe
  adb shell su -c 'am start -n local.penprobe/.ProbeActivity --es mac <PEN_MAC> --ez disable true' # switch all CCCs back off
  adb uninstall local.penprobe
  ```
  Closing it by killing or removing its task skips the cleanup, so always finish with `--ez disable true`.
  In desktop-windowing mode, Back may not reach its window.
- The pen sleeps after about a minute idle; thumb touches don't wake it, but moving it or hovering near the screen does.

## Next steps (not started)
1. Get the **stock OxygenOS pen app** for OPD2403. Download only the pen-related APK(s) from a public
   firmware dump, not the whole firmware, and decompile it (`jadx`).
2. From it, extract: the haptics ("textured vibration") command format and characteristic; whether
   stock sends an "enable gestures" command that makes the button report more than `01`; and the
   actions the stock thumb-button setting offered.
3. Prototype, asking before **every** write to the pen:
   - thumb button → configurable action (e.g. eraser toggle, undo, screenshot), from `180938ac` notifications,
   - haptics while writing, using the decoded command.
4. Long term: extend LineageOS's `org.lineageos.pen` (Apache-2.0, in `android_hardware_oplus`) to
   support the Stylo 2 service layout. That would be the upstream-friendly home for this.
