# OnePlus Pad 2 Smart Keyboard over Bluetooth on AOSP ROMs

A KernelSU module (Magisk-compatible layout) that lets the **OnePlus Pad 2 Smart Keyboard** work
**detached over Bluetooth LE** on AOSP-based ROMs (tested on PixelOS 17 for `caihong`). On these ROMs
the keyboard normally only works while attached to the pogo pins.

This is a personal port of **[Drun555/oneplus-pad3-keyboard-ble](https://github.com/Drun555/oneplus-pad3-keyboard-ble)**
(OnePlus Pad 3 module v1.7). All credit for the original approach goes to that project. The port, the
analysis and this repo were produced with an AI assistant (Claude); the upstream module is credited
as AI-generated too.

> **Status:** works on the author's tablet. Use at your own risk. The module edits
> `/data/misc/bluedroid/bt_config.conf` (with a backup, and undone on uninstall).
> Upstream has no license file, so this repo doesn't add one either.

## What it does
| Problem on AOSP | Fix |
|---|---|
| The keyboard's HID report map is 561 bytes; Android reads only 512 over GATT. The kernel rejects the truncated map (`item fetching failed at offset 511/512`), so **no keys work**, and Android 17 then marks the keyboard "unsupported" and forbids reconnecting | Appends the missing 49 bytes to the cached map (validated before writing), before Bluetooth starts or with one Bluetooth restart after a new bond |
| The firmware declares a 70 × 41 cm touchpad, so the BLE pointer moves ~6× too fast | Corrects the declared size to the real 120 × 71 mm (23 units/mm, same as the pogo touchpad) |
| Double input while attached | On attach: HID policy *forbidden* + disconnect. On detach: *allowed* + connect |
| Laggy touchpad | A small companion app requests the high-priority (~15 ms) BLE connection interval |

Attach/detach is detected from the pogo driver's uevent (`pogo_keyboard`, `pogopin_status`), with a
`dumpsys input` poll as a fallback.

## Use
1. **Edit `module/config.sh`**: at minimum `KBD_MAC`, your keyboard's BLE address (Settings → Bluetooth
   after pairing, or in the pogo uevent `mac_addr`). The release zip is built for the author's keyboard.
2. Build (below), then `ksud module install <zip>` (or install from the KernelSU / Magisk app) and reboot.
3. Unlock the tablet once after boot; detach the keyboard; accept the pairing prompt the first time.

Log: `/data/local/tmp/pad2kbd.log`. Status: the module's **Action** button.
Uninstall: remove the module and reboot; `uninstall.sh` undoes every change.
Details, recovery commands and test results: [`docs/NOTES.md`](docs/NOTES.md).

## Build
Needs a JDK (21), Android build-tools (`d8`, `aapt2`, `zipalign`, `apksigner`) and an `android.jar` (API 34+).
```
KS_PASS=<your keystore password> tools/build.sh   # creates tools/pad2kbd-release.jks on first run
# -> build/OnePlus_Pad2_Keyboard_BLE-v<version>.zip
```
Keep your keystore: later app updates must be signed with the same key.

## Layout
| Path | Contents |
|---|---|
| `module/` | Module scripts; all device values in `config.sh` |
| `PogoPair/`, `HidCtl/` | Companion app (pairing + latency) and the root `app_process` HID-policy helper |
| `tools/` | `build.sh`, `hid_parse.py` (HID descriptor walker), `policy_watch.sh` (debug watcher), `gatt_cache_dump.py`, `penprobe/` (Stylo 2 GATT probe) |
| `docs/` | `STYLO2.md` (Stylo 2 thumb button / haptics research, in progress), `ANALYSIS.md` (how the Pad 3 module works), `COMPARISON.md` (Pad 3 vs Pad 2), `EXTRACTED.md` (collected Pad 2 values + experiments), `NOTES.md` (install/recovery/tests), `pad2_vs_pad3.diff` |
| `release/` | The build installed on the author's tablet (contains the author's keyboard MAC) |

The docs were written during development and refer to the original working folders: `pad2_module/` →
`module/`, `pad2_src/` → `PogoPair/` + `HidCtl/`, `pad2_data/` (raw collection, not published).

## Known limitations
- KernelSU without a mounting metamodule doesn't overlay `system/`, so the companion app is installed as a normal app.
- After a long time on the pins, the first detach can take ~13 s: the keyboard's radio is slow to start advertising.
- Attach/detach handling starts after the first unlock following a boot.
