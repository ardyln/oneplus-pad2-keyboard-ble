# OnePlus Pad 2 Smart Keyboard over Bluetooth on AOSP ROMs

A KernelSU module (Magisk-compatible layout) that lets the **OnePlus Pad 2 Smart Keyboard** work
**detached over Bluetooth LE** on AOSP-based ROMs (tested on PixelOS 17 for `caihong`). On these ROMs
the keyboard normally only works while attached to the pogo pins.

This is a port of **[Drun555/oneplus-pad3-keyboard-ble](https://github.com/Drun555/oneplus-pad3-keyboard-ble)**
(OnePlus Pad 3 module v1.7). All credit for the original approach goes to that project. The port, the
analysis and this repo were produced with an AI assistant (Claude); the upstream module is credited
as AI-generated too.

> **Status:** works on the author's tablet. Use at your own risk. The module edits
> `/data/misc/bluedroid/bt_config.conf` (with a backup, and undone on uninstall).
> Upstream has no license file, and its author has been contacted about this port; until that's
> settled this repo doesn't add a license of its own.

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
1. Download the zip from [Releases](https://github.com/ardyln/oneplus-pad2-keyboard-ble/releases) and
   install it with KernelSU (Magisk should work too, but hasn't been tested), then reboot.
2. Unlock the tablet once after boot. If Android asks you to allow installing the module's app,
   allow it (with the Stylo 2 module installed too, a second prompt follows for its app). Then
   **attach the keyboard**: the module reads the keyboard's Bluetooth address from the pogo
   connection, so there's nothing to look up or type in.
3. Detach the keyboard and accept the pairing prompt the first time.

### Which keyboard
The module finds the keyboard's address by itself, in this order:
1. `KBD_MAC` in `module/config.sh`, if you build the module for one keyboard (empty by default);
2. `/data/adb/pad2kbd/keyboard_mac`, if you pin a keyboard there (see below);
3. the keyboard attached right now: the pogo driver writes its address to the kernel log about every
   100 ms while it's attached;
4. the last keyboard that was attached;
5. the paired OnePlus keyboard in Android's Bluetooth settings, if exactly one is paired.

So a different keyboard is picked up as soon as you attach it. To always use one keyboard, for example
with several paired, pin its address without rebuilding (it survives module updates):
```
su -c 'echo AA:BB:CC:DD:EE:FF > /data/adb/pad2kbd/keyboard_mac'   # remove the file to go back to automatic
```
The module's **Action** button shows the address in use and where it came from.

Later versions show up as module updates in KernelSU (from this repo's releases); changes per
version are in [CHANGELOG.md](CHANGELOG.md).

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
| `module/` | Module scripts; all device values in `config.sh` (the keyboard's address is detected, see above) |
| `PogoPair/`, `HidCtl/` | Companion app (pairing + latency) and the root `app_process` HID-policy helper |
| `tools/` | `build.sh`, `hid_parse.py` (HID descriptor walker), `policy_watch.sh` (debug watcher) |
| `docs/` | `ANALYSIS.md` (how the Pad 3 module works), `COMPARISON.md` (Pad 3 vs Pad 2), `EXTRACTED.md` (collected Pad 2 values + experiments), `NOTES.md` (install/recovery/tests), `pad2_vs_pad3.diff` |
| `release/` | The current build, also attached to the GitHub releases |

The docs were written during development and refer to the original working folders: `pad2_module/` →
`module/`, `pad2_src/` → `PogoPair/` + `HidCtl/`, `pad2_data/` (raw collection, not published).

## Known limitations
- KernelSU without a mounting metamodule doesn't overlay `system/`, so the companion app is installed as a normal app
  (after the uevent listener has started, so attach/detach work even if that install fails).
- After a long time on the pins, the first detach can take ~13 s: the keyboard's radio is slow to start advertising.
- Attach/detach handling starts after the first unlock following a boot.

## OnePlus Stylo 2

The Stylo 2 research (thumb button, writing haptics) that started here has moved to its own module:
**[oneplus-pad2-stylo2](https://github.com/ardyln/oneplus-pad2-stylo2)**, including the research log,
the protocol, `penprobe` and `gatt_cache_dump.py`.
