# Pad 3 module assumptions vs OnePlus Pad 2 (`caihong`, PixelOS 17, KernelSU)

| # | Pad 3 assumption | Pad 2 value | Status |
|---|---|---|---|
| 1 | Keyboard link is plain BLE HOGP | HOGP (VID/PID stored as `Hogp*`, service bonded over LE) | **same** |
| 2 | Keyboard advertises after a physical detach | Yes, it was bonded over LE while detached | **same** |
| 3 | MAC `XX:XX:XX:XX:XX:XX` | `XX:XX:XX:XX:XX:XX` (same OUI) | **different** |
| 4 | VID 8921 / PID 14441 | 8921 / 14441 | **same** |
| 5 | Report map 561 B, Android stores 512 | Stored 512 B, truncated mid-item at byte 511 | **same** (patch needed) |
| 6 | Descriptor tail (49 B) | The Pad 3 tail completes the Pad 2 map into a valid 561 B descriptor | **same** (inferred, high confidence) |
| 7 | Truncated lengths 1208/1210 hex (older broken patches) | Never applied on Pad 2 | **not applicable** (harmless to keep) |
| 8 | uevent `DEVNAME=pogo_keyboard`, `pogopin_status` 0/1 | identical (`SUBSYSTEM=pogopin`) | **same** |
| 9 | Input device `pogo_touchpad` when attached | `pogo_touchpad` + `OnePlus Pad Smart Keyboard` | **same** |
| 10 | busybox `/data/adb/ksu/bin/busybox` | same path, has `uevent` | **same** |
| 11 | Root manager KernelSU | KernelSU 3.3.0 (no Magisk) | **same** |
| 12 | KernelSU doesn't mount `system/`, so the APK is installed as a user app | **Same.** KernelSU 3.x without a mounting metamodule doesn't mount `system/`. (I first misread bindhosts as proof that it does; bindhosts has `skip_mount` and bind-mounts itself.) v0.2 installs the APK as a normal app. | **same** |
| 13 | Hidden API: `HidCtl` via root `app_process` (Android 15/16 framework) | Works unchanged on Android 17, with **no** global `hidden_api_policy` change | **same** (verified in Phase 5) |
| 14 | `bt_config.conf` at `/data/misc/bluedroid/` | same | **same** |
| 15 | No MAC on the pogo side | The pogo UART frame carries the MAC (dmesg only, no sysfs node) | **used since v0.8:** the module reads the attached keyboard's address from these frames |
| 16 | HID_HOST policy stays ALLOWED until the module changes it | The Android 17 stack **auto-forbids** it 10 s after connecting, because the 512-byte map fails the kernel HID parser (`item fetching failed at offset 511/512`). Confirmed by experiment; see `pad2_data/EXTRACTED.md` | **different**: fix the descriptor *before* connecting, then `HidCtl resume` (policy 100) |

## Key questions from the brief
- **Is the report map over 512 bytes?** Yes, 561. The descriptor patch is needed, with the same tail.
- **Does the keyboard appear as a BLE device after detach?** Yes. It was connectable and bonded over LE while detached. No pogo-side wake step is needed, so we don't have to investigate stock's handover.

## Recommendation
Do a **direct port**. The Pad 2 keyboard is the same hardware family (identical VID/PID, report map, uevents and input names). The only device-specific value that differs is the MAC. Planned changes for `pad2_module/`:

1. Put all values in `config.sh`: MAC, VID/PID, uevent and input names, tail, busybox path, log file.
2. Rebuild `PogoPair` from source, with the MAC read at runtime from the intent extra or `config.sh`, and no hardcoded MAC or MAC filter. Use a new package id (`local.pad2kbd.pogopair`) so it can't collide with the Pad 3 app. Sign it with a new local key. Ship it as a real priv-app, because overlays work here, so `BLUETOOTH_PRIVILEGED` is actually granted. Make the receiver and service non-exported, or protected by a signature permission.
3. Hidden-API policy: try the port **without** the global `hidden_api_policy` change. As a priv-app with `BLUETOOTH_PRIVILEGED` it can call the SystemApi `createBond`/HID methods, and `HidCtl` runs from `app_process`, where hidden-API checks don't apply. Re-enable the policy only if a test proves it's needed. If it is, `uninstall.sh` restores the previous values.
4. `descriptor-fix.sh`: back up `bt_config.conf` to `/data/adb/pad2kbd/` once before the first edit, write atomically, and refuse (log, no Bluetooth restart) if the result doesn't validate. Limit Bluetooth restarts to one per new bond, so it can never loop.
5. Log everything to `/data/local/tmp/pad2kbd.log`, with size rotation.
6. Add an `uninstall.sh` that does the following: set HID_HOST policy back to 100, remove the deviceidle whitelist entry, restore the hidden-API settings if they were changed, and put back the original 512-byte `HogpDescriptor` line only (not the whole backup, so pairings made since are kept).
7. In Phase 5, **before** installing: remove the old Pad 3 module, its `local.codex.pogopair` app and whitelist entry, and reset `hidden_api_policy*`. I'll ask for each.

**Residual risks.** The 49-byte tail is inferred: worst case the touchpad misbehaves, while the keyboard keys work regardless. `HidCtl` may need changes for Android 17. Both are caught in Phase 5 testing.

## Added after testing
- **Touchpad size bug (also in the Pad 3 firmware, presumably):** the BLE map declares Physical Max = Logical Max (2764 x 1630, unit 0.01 in, i.e. 70 x 41 cm), so the BLE touchpad got ~4 units/mm vs the pogo touchpad's 23 and moved ~6x too fast. v0.2 swaps the 10 Physical Max items to 4.73 x 2.79 in, giving 23 units/mm (verified with `getevent -lp`).
