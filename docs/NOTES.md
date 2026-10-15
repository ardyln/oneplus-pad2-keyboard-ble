# OnePlus Pad 2 Keyboard BLE: notes

Port of Drun555's Pad 3 module. The upstream repo has no license file; its author has been contacted about this port.

- Zip: from the [releases](https://github.com/ardyln/oneplus-pad2-keyboard-ble/releases) (also in `release/`), built by `tools/build.sh` from `module/`, `PogoPair/` and `HidCtl/`. Older versions are superseded (see Iterations); KernelSU offers new ones as module updates.
- Module id `pad2_keyboard_ble`; companion app `local.pad2kbd.pogopair`, signed with a personal key (`tools/pad2kbd-release.jks`, not in the repo). KernelSU here doesn't mount `system/` (no metamodule), so `service.sh` installs it as a normal app (`/data/app`), after starting the uevent listener. `uninstall.sh` removes it.
- Device values are in `config.sh`. The keyboard's address isn't one of them anymore: the module reads it from the pogo connection while the keyboard is attached (or takes the last one found, or the only paired OnePlus keyboard). A different keyboard is picked up when it's attached; to pin one, write its address to `/data/adb/pad2kbd/keyboard_mac`.
- Log: `/data/local/tmp/pad2kbd.log` (rotates at 256 KB), plus logcat tag `pad2kbd`
- State/backups: `/data/adb/pad2kbd/` (root only). `bt_config.conf.orig` there contains link keys: never copy it off the tablet.

## Before installing, if the Pad 3 module was ever installed
| Step | Command | Undo |
|---|---|---|
| Remove Pad 3 module | `adb shell su -c 'ksud module uninstall oneplus_pogo_keyboard_ble'` (takes effect on reboot) | reinstall its zip |
| Remove its app | `adb shell su -c 'pm uninstall local.codex.pogopair'` | `pm install` its APK |
| Remove its idle whitelist entry | `adb shell su -c 'cmd deviceidle whitelist -local.codex.pogopair'` | `… whitelist +local.codex.pogopair` |
| Reset hidden-API policy | `adb shell su -c 'settings delete global hidden_api_policy; settings delete global hidden_api_policy_p_apps; settings delete global hidden_api_policy_pre_p_apps'` | `settings put global <name> 1` |

## Install
```
adb push OnePlus_Pad2_Keyboard_BLE-v<version>.zip /data/local/tmp/
adb shell su -c 'ksud module install /data/local/tmp/OnePlus_Pad2_Keyboard_BLE-v<version>.zip'
adb reboot
```
Or use the KernelSU app: **Modules → Install from storage**. Magisk (`magisk --install-module <zip>`) should work too but has never been tested.
After the reboot, unlock once and attach the keyboard, so the module can read its address.

## Uninstall
KernelSU app: **Modules → remove**, then reboot, or `adb shell su -c 'ksud module uninstall pad2_keyboard_ble'` and reboot.
On the next boot `uninstall.sh` does the following:
- restores the original 512-byte `HogpDescriptor` line, reversing the touchpad size swap too (only that line, so pairings made since are kept),
- removes the deviceidle whitelist entry and uninstalls the companion app,
- restores `hidden_api_policy*` (only if the module changed them; it doesn't by default),
- sets the keyboard's HID policy to "allowed",
- deletes `/data/adb/pad2kbd/`.

## If something goes wrong
- **Disable without uninstalling:** `adb shell su -c 'ksud module disable pad2_keyboard_ble'`, then reboot (`… enable …` to undo).
- **Bootloop / no adb after boot:** KernelSU safe mode. Press **Volume Down** repeatedly (3+ times) while the device boots; all modules are then disabled for that boot. Then disable or uninstall this module as above. From a recovery with `/data` access: `rm -rf /data/adb/modules/pad2_keyboard_ble`.
- **Bluetooth broken after the descriptor edit:** with Bluetooth off, `su -c 'sh /data/adb/modules/pad2_keyboard_ble/descriptor-fix.sh restore'`. As a last resort, restore `/data/adb/pad2kbd/bt_config.conf.orig` over `/data/misc/bluedroid/bt_config.conf` (owner `bluetooth:bluetooth`, mode 0660) while Bluetooth is off. That undoes pairings made after the backup.
- **Status at any time:** the KernelSU **Action** button on the module, or `adb shell su -c 'sh /data/adb/modules/pad2_keyboard_ble/action.sh'`

## Known issues / design notes
- The 49-byte report-map tail is inferred from the Pad 3 module, not read from this keyboard. It fits exactly (see `pad2_data/EXTRACTED.md`). If it's ever wrong, the kernel rejects the whole map, keys included. `descriptor-fix.sh` validates the joined map before writing.
- Android 17 forbids the keyboard 10 s after a failed HID probe (`Disabling HID connection for unsupported device`). The module therefore repairs the map first and re-allows the policy on every detach.
- Each new bond (first pairing, re-pair, Bluetooth reset) causes **one Bluetooth restart** about 3 s after bonding. Other Bluetooth devices drop briefly. There's a limit of 3 restarts per boot.
- The global hidden-API exemption is **off** (`HIDDEN_API_POLICY=0`), and testing showed it isn't needed.
- **Touchpad size fix:** the keyboard firmware declares a 70 x 41 cm touchpad. `DESC_SWAPS` in `config.sh` corrects it to the real 120 x 71 mm (23 units/mm, the same as the pogo touchpad). Set it to empty to disable.
- `service.sh` waits for the first unlock after boot (`sys.user.0.ce_available`). Until then, attach/detach isn't handled; the stored map is already fixed at that point.
- **Shutdown:** at reboot the pogo driver loses the keyboard heartbeat and sends a *real* `pogopin_status=0` uevent. `adb reboot` doesn't set `sys.shutdown.requested`, and Android 17's init doesn't store `sys.powerctl`. The module also checks `persist.sys.boot.reason` (empty at runtime, set by init when shutdown starts) and `init.svc.zygote`, and ignores mode changes during shutdown. A 2 s debounce was tried in v0.5/v0.6 and removed, because it delayed every real detach. If a false detach ever slips through, it's harmless: it's killed, or it leaves the policy at "allowed" until the next unlock.
- **First detach after a long attach is slow (~13 s observed):** the keyboard's own radio takes that long to start advertising after it switches from pogo power to battery (no Bluetooth activity at all in that window). Detaches shortly after a previous one take 0.2–0.8 s. The keyboard firmware does this; the tablet can't speed it up.
- **Privacy:** the pogo uevent and kernel log include the keyboard's **serial number** (`report_sn`), and the pogo frames its Bluetooth address. The module never logs uevent contents; it reads only the address from the frames. Saved data in `pad2_data/` has these redacted.
- **App install from `service.sh` (fixed in v0.9):** `pm` hands its stdin and output to `system_server`. A pipe (`out=$(pm install …)`) stays open while an install waits, so the script waited for good, and a file under `/data/adb` is refused (`Failed transaction`). That stopped attach/detach after a reinstall. `pm` now reads from `/dev/null` and writes to a file in `/data/local/tmp`, with a 2-minute limit, and the app is only recorded as installed when that worked.

## Test results (PixelOS 17 caihong, KernelSU 3.3.0; 2026-10-13 unless noted)
Logs: `pad2_data/phase5_tests/` (module log + filtered logcat, no keys).

| # | Test | Result |
|---|---|---|
| 1 | Typing while attached, no double input | **Pass.** `hidctl suspend` → policy 0, BLE HID disconnected |
| 2 | Detach → type over BLE | **Pass.** `resume` → policy 100, HID connected, kernel accepted the 561-byte map |
| 3 | Touchpad while detached | v0.1: worked but ~6x too fast. **v0.2: pass**, 23 units/mm, latency helper `High-priority BLE interval accepted=true` |
| 4 | Re-attach → clean switch back | **Pass.** No double input; latency helper stopped |
| 5 | Detach again after a reboot | **Pass.** No Bluetooth restart needed (map already fixed at post-fs-data) |
| 6 | New bond: forget → detach → accept the pairing prompt (v0.3) | **Pass.** Module bonded via `createBond(LE)`; kernel rejected the 512 B map; module restarted Bluetooth once (5 s after bonding, before Android's 10 s forbid); keyboard typing 7 s after bonding |
| 7 | Uninstall (v0.3 → v0.4 retest) | v0.3: map restored, app/whitelist/state removed, but `hidctl allow` crashed (rc=139, early mount namespace without ART). **v0.4: pass**, all items undone, policy set to allowed. Android re-forbids it 10 s later because the restored 512 B map fails, which is stock behaviour. |
| 8 | No false detach at shutdown | v0.3–v0.5: still logged. v0.6/v0.7: **pass** on 3 reboots |
| 9 | Real-detach regression (v0.7) | **Pass.** BLE input 0.2–0.8 s after the detach uevent; first detach after a long attach ~13 s (keyboard-side, see Known issues) |
| 10 | Address detection (v0.8, 2026-10-15) | **Pass.** With the cache deleted, the address was read from the pogo frames and matched the paired keyboard; detach → BLE (`resume`, rc=0), attach → pogo (`suspend`, rc=0); a pinned address took precedence |
| 11 | Remove and reinstall the module, reboot (v0.9, 2026-10-15) | **Pass.** v0.8 had hung on the app install (attach/detach stopped working). v0.9: the listener started first, the app installed at boot (`Success`), attach handled |

Iterations:
- v0.1: the priv-app was never mounted (KernelSU without a metamodule).
- v0.2: added user-app install fallback and the touchpad Physical-Max correction.
- v0.3: ignore mode changes when `sys.shutdown.requested` is set (not enough for `adb reboot`).
- v0.4: run `HidCtl` via `nsenter -t 1 -m` (fixes the uninstall crash); also check `sys.powerctl`; treat an empty `dumpsys input` as unknown.
- v0.5: 2 s detach debounce + trigger-source logging. Logcat showed the real cause: a genuine kernel uevent at reboot.
- v0.6: also check `persist.sys.boot.reason` and `init.svc.zygote`.
- v0.7: removed the 2 s debounce (it delayed every real detach); kept the instant shutdown check and source logging.
- v0.8: the keyboard's address is detected (pogo frames, cache, or the paired keyboard) instead of being set in `config.sh`; a pinned address can override it; module updates through KernelSU.
- v0.9: the app install can't block the boot script anymore (see Known issues), and the uevent listener starts first; installer shows "by ardy".
