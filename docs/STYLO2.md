# OnePlus Stylo 2: thumb button and haptics (research notes)

> The result of this research is a separate module: **[oneplus-pad2-stylo2](https://github.com/ardyln/oneplus-pad2-stylo2)**
> (writing haptics, thumb-button shortcuts, Saber integration). Its `docs/RESEARCH.md` continues these notes.

Status as of 2026-10-14: **writing haptics fully work on PixelOS** (see "Test results"): all textures, all
levels, off, and the one-shot buzz. The only pen writes so far are CCC descriptors and stock commands
(`2c 90 01 01 0x`, `2c 94 …`, `2c 92 01 02 ff 02`).

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
| `18093398-2a69-11ec-8d3d-0242ac130003` / **`180938ac-…`** | notify | **Thumb button**: `01` per **double tap** (corrected 2026-10-14; single taps, holds and slides send nothing). Events can come ~0.4 s apart. Doesn't wake a sleeping pen. Only sent while other notifications are subscribed too |
| `18093398-…` / `1809396a-…` | notify | On the magnetic charger: `20` attached, `21` detached (with `chg evt …` on the console). Corrected 2026-10-14; first noted the other way round |
| `18093398-…` / `180937bc-…` | notify | Battery level (`64` = 100 %) |
| `18093398-…` / `180932da-…` | notify | not seen yet |
| `18092dbc-…` / `18093046-…` | write, notify | Pencil status `2c900101` + `00` idle / `01` active (LineageOS already decodes/acks this) |
| `18092dbc-…` / `1809314a-…` | read | battery percent (`64` = 100 %, `60` = 96 %) |
| `18092dbc-…` / `18093212-…` | read | unknown: read `21` both on and off the magnet; not the charger state |
| `6e400001-b5a3-f393-e0a9-e50e24dcca9e` (Nordic UART) / `6e400003` | notify | **Firmware debug console**, plain text: `sleep enter/exit`, `film 24` (thumb touch), `chg evt …`, `rx <hex> …` stats every 5 s while awake |
| NUS / `6e400004` | notify | not seen yet |
| NUS / `6e400002` | write | console input? **Do not write blindly** |
| `a6ed0401-d344-460a-8075-b9e8ec90d71b` / `a6ed0402` notify, `a6ed0403` write, `a6ed0404` write+indicate | | **Goodix firmware update (DFU)** (`DfuProfile` in the stock app). **Never write** |
| `58480000-5a6a-1122-3300-004095112200` / `58480001` | write, notify | Unknown; possibly firmware update (**don't touch**) |

The full GATT table came from the tablet's cache `/data/misc/bluetooth/gatt_cache_<penaddr>`, decoded
with `tools/gatt_cache_dump.py`.

## Stock protocol (from the OxygenOS app)
Source: `com.oplus.ipemanager` ("Smart accessories") 15.0.30 from APKMirror, file SHA-256
`aa4a6e8b…a926e7802`, signed by the Oplus certificate (SHA-256 `b0a9bbfc…6d8c818`), decompiled with
jadx 1.5.6. Main class: `com.oplus.ipemanager.btadsorb.ble.PencilBleManager`. The decompiled code is
not kept in this repo.

**Commands** are written to `18093046` (`UUID_INTERFACE_COM_WRITE_CHARACTER`) as
`2c <cmd> <len> <payload…>`:

| Bytes | Stock name / meaning |
|---|---|
| `2c 08 01 01` | queryBatteryLevel |
| `2c 06 01 05` | queryFwVersion |
| `2c 25 01 03` | queryHwVersion |
| `2c 26 01 0b` / `2c 26 01 0d` | queryPencilType |
| `2c 53 01` | querySerialNum. **Never send** (we don't collect serials) |
| `2c 38 01 01` / `2c 39 01 01` | magnet (hall) in / out |
| `2c 90 01 01 01` / `… 00` | pencil enabled / disabled (`settings_enable_oppo_pencil`) |
| `2c 92 01 02 ff 02` | **one-shot vibration** (SDK `FUNCTION_VIBRATION`) |
| `2c 94 02 <type> <level+1>` | **writing texture**: type 0 pencil, 1 eraser, 2 ballpen, 3 pen; level default 2 (sent as `03`). Sent on connect (`initFeedbackTypeAndLevel`) and when the setting changes |
| `2c 91 01 00`, `2c 93 01 00` | not decoded yet |

**Textured vibration while writing is not driven over BLE.** The SDK calls `startFeedBackVibration()` /
`stopFeedBackVibration()` map to `OplusTouchNodeManager.writeNodeFileByDevice(0, 38, "3" / "2")`.
Node 38 in the touch HAL table (`/odm/bin/hw/vendor-oplus-hardware-touch-V2-service`) is
**`/proc/touchpanel/pencil_control`** (0666). In the NT36532 driver, `3` sends
`EVENTBUFFER_EXT_PEN_VIBRATOR_ON` and `2` sends `…_OFF` to the touch IC. All other values are rejected,
and writes are ignored while the screen is off. So the digitizer drives the pen motor, and BLE only selects
the texture and strength. On stock, apps such as Notes call start/stop through the SDK
(`com.oplus.ipemanager.ACTION.PENCIL_SDK`, permission `com.oplus.permission.safe.IOT`).

Confirmed by [stylo2-haptics](https://github.com/YeetingWaterbottle/stylo2-haptics) (XDA "Global Haptic
Feedback" module, tested on a Pad 3 with OxygenOS). It binds to the stock SDK as a priv-app and calls
`setVibrationType` + `startFeedBackVibration` **once from a toggle**, and haptics then work while writing
in every app. So the touch IC handles "is the pen writing" by itself: one `3` is enough, and nothing has to
follow the strokes. It still needs the stock ipemanager service, so it can't run on AOSP. That repo has no
license, so only these facts are reused here, no code.

**Thumb button:** stock also gets just one event. A `180938ac` notification makes it broadcast
`com.oplus.ipemanager.action.PENCIL_DOUBLE_CLICK` (permission
`com.oplus.ipemanager.permission.receiver.DOUBLE_CLICK`), and apps act on it according to
`Settings.Global ipe_pencil_double_click`. There is no "enable gestures" command.

## Test results (2026-10-14, PixelOS 17)
- `3` → `pencil_control` alone: **no vibration**. Touch IC accepted it (reads back `3`) and saw pen-down events.
- Then over BLE (penprobe `--es cmd enable,texture`): `2c 90 01 01 01`, `2c 94 02 00 03`, both `status=0`.
  Right before, the pen had reported `2c 90 01 01 00`. → **Texture felt while writing, in any app.**
- Still works after screen off/on, and after attaching and detaching the pen on the magnet.
- In the pen's `2c 90 01 01 xx` status notifications, `xx` is `01` when the pen is off the magnet and
  `00` when it's on it (same as `1809396a` `21`/`20`), so it means "active", not "enabled".
- Still works after the pen sleeps (console `sleep exit`) and wakes.
- `2c 90 01 01 00` (stock "disabled"): **texture still felt**, so `2c 90` is not the switch.
- Bluetooth off/on (pen reconnects): **texture gone**. `pencil_control` still read `3`.
- After the reconnect, only `2c 94 02 00 03`: **texture back**.

- Types at default level: 1 eraser "more subtle, still friction"; 2 ballpen "even more subtle?"; 3 pen
  "subtle but consistent"; 0 pencil the clearest.
- Pencil level 0 (`…00 01`): barely noticeable. Level 4 (`…00 05`): "definitely stronger than anything else".
- `2c 92 01 02 ff 02` (one-shot): single buzz felt, no screen contact needed.
- `2` → `pencil_control` with texture set: **still vibrates**. After a Bluetooth reconnect with
  `pencil_control` = `2`, `2c 94 02 00 05` alone: **vibrates**. → **`pencil_control` is not needed on the
  Pad 2.** (The very first attempt failed only because the pen hadn't received `2c 94` yet.)
- `2c 94 02 00 00` (level byte `00`, what stock sends when the "writing feedback" switch is turned off,
  `setWrittenFeedbackState`): **vibration gone**.

**Recipe:** everything is in the pen, over BLE on `18093046`:
- on: `2c 94 02 <type 0-3> <level 0-4 + 1>`, off: `2c 94 02 <type> 00`;
- the pen forgets it on every Bluetooth reconnect, so send it after each connection; it survives pen sleep,
  the magnet and screen off/on;
- one-shot buzz: `2c 92 01 02 ff 02`.
`/proc/touchpanel/pencil_control` (stock's `startFeedBackVibration`) has no effect we could feel here. It may
matter for other tablets or touch ICs. Its value after these tests is `2`; it read `0` before and resets on reboot.

## Tools
- `tools/gatt_cache_dump.py FILE`: decodes an Android `gatt_cache_*` file into services and characteristics.
- `tools/penprobe/`: a debug app (`local.penprobe`). It subscribes to every vendor notify/indicate
  characteristic, reads the readable ones (it never reads the standard Serial Number characteristic),
  and logs everything to the screen and to logcat tag `PenProbe`. Besides CCC descriptors it can write
  only the allowlisted commands: `enable`, `disable`, `texture`, `texture-off`, `oneshot`, and `texture:T:L`
  (type 0-3, level 0-4; anything else is refused), named with e.g. `--es cmd texture:0:4`.
  Use `am start -S …` when it is already running; otherwise the intent goes to the old instance and nothing is sent.
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

## Next steps
1. Service (KernelSU module, priv-app), written from this spec only: on each pen BLE connection send the
   chosen texture (or off); settings for type, level and on/off; thumb button (`180938ac`) →
   `KEYCODE_STYLUS_BUTTON_*` or a chosen action, with an optional `oneshot` buzz as confirmation.
2. Long term: extend LineageOS's `org.lineageos.pen` (Apache-2.0, in `android_hardware_oplus`) to
   support the Stylo 2 service layout. That would be the upstream-friendly home for this.
