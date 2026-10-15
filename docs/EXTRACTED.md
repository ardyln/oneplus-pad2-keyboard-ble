# Pad 2 keyboard values (extracted 2026-10-13, PixelOS 17 `caihong`, KernelSU 3.3.0)

Raw collection: `pad2kbd_aosp_20261013_135424/` (+ `.tar.gz`), summary in its `SUMMARY.txt`.
Collected with `tools/pad2_kbd_collect_adbsu.sh` (copy of `Downloads/pad2_kbd_collect.sh` + an `adb shell su` mode).
Checked: no `LinkKey`/`LE_KEY_*` values, IMEI or serial number in any file. Only key *type names* appear in `bt_manager.txt`.
Note: `dmesg.txt`/`logcat.txt` contain raw pogo UART frames (`POGO_KB … show_buf`), i.e. keyboard traffic while attached. Keep these files private.

| Item | Value | Source |
|---|---|---|
| Keyboard BLE MAC | `XX:XX:XX:XX:XX:XX` (public address, LE-only) | `bt_config_nokeys.txt` section; also inside every pogo frame, little-endian (the module reads it from there, see `resolve_kbd_mac` in `module/common.sh`) |
| VID / PID | 8921 / 14441 (0x22D9 / 0x3869), same as the Pad 3 keyboard | `HogpVendorId/HogpProductId`, and the pogo input devices `Vendor=22d9 Product=3869` |
| Stored report map | 512 bytes (1024 hex), the same in all three snapshots (md5 of line `a40241902b67…`) | `HogpDescriptor` |
| Truncation point | Byte 511 = `0x55` (Unit Exponent), its 1-byte argument cut off | `tools/hid_parse.py` |
| Full report map | **561 bytes**: first 512 bytes + the Pad 3 49-byte tail. It parses cleanly, all collections close, Report ID 3 = 29 bytes (5 × 5-byte contacts + 16-bit scan time + count + button), IDs 1 = 8 B keyboard and 2 = 2 B consumer | Inference, see "confidence" below |
| Pogo uevent | `SUBSYSTEM=pogopin`, `DEVPATH=/devices/virtual/pogopin/pogo_keyboard`, `DEVNAME=pogo_keyboard`, `ACTION=change`, `pogopin_status=1` attach / `0` detach | `uevents.txt` |
| Pogo input devices (attached only) | `OnePlus Pad Smart Keyboard`, `pogo_touchpad` (Bus 0x19, 22d9:3869); `pogo_wakeup` (8286:8002) is always present | `input_devices.txt` |
| Pogo kernel driver | `tinno,pogo_keyboard` (`/sys/bus/platform/drivers/tinno,pogo_keyboard`), char dev `pogo_keyboard` 473:0, vendor HAL `vendor.oplus.hardware.pogo_keyboard-service` | `sysfs_pogo.txt`, `ps` |
| Pogo frame | 31 bytes about every 100 ms while attached: `55×8 f1 a1 a2 2f 0b 05 02 00 03 <MAC LE ×6> 00 69 af fe aa×4` | dmesg `POGO_KB: pogo_keyboard_recv` |
| BLE after detach | Yes. The bond was made over LE while the keyboard was detached (nRF Connect, 13:49:03–13:49:10, `CONNECTED`, `BOND_STATE_BONDED`) | `bt_manager.txt` |
| HID_HOST connection policy now | **0 (FORBIDDEN)**. It went `-1 → 100` at bond (13:49:10), then `100 → 0` at 13:49:20, cause not logged | `bt_manager.txt` |
| busybox | `/data/adb/ksu/bin/busybox` (has the `uevent` applet) | collector |
| KernelSU `system/` overlay | Works on this ROM (bindhosts' `/system/etc/hosts` is active) | `/system/etc/hosts` line count |

## Values only obtainable on stock / not obtained
- **Bytes 512–560 of the report map** can't be read on any Android build over GATT. The Pad 3 tail is a near-certain fit (same VID/PID, exact item boundary at 511/512, 29-byte touchpad report matching the module author's description, standard Precision-Touchpad scan-time encoding). It is still **inferred, not measured**. The direct check would be an ATT Read Blob at offset 512 from this PC's own Bluetooth adapter, which needs a separate pairing.
- Stock OxygenOS's handover logic (how stock uses the MAC in the pogo frame) wasn't observed. It isn't needed, because the keyboard advertises on detach without it.
- btsnoop was skipped by agreement (no extra data over 512 bytes, and it would contain LTKs).

## Experiment 2026-10-13 14:03–14:05: why the HID_HOST policy keeps flipping to FORBIDDEN
Logs: `experiment_hid_policy/` (`watch.txt` = policy/connection timeline, `bt_hid_logcat.txt` = filtered BT/HID logcat, no keys).

Sequence each time "Input device" was toggled on while detached (it reproduced twice):
1. `HID_HOST policy 0 -> 100`, HOGP connects, `bta_hh_co_send_hid_info vid 0x22d9 pid 0x3869`, using the cached **512-byte** map.
2. Kernel: `hid-multitouch 0005:22D9:3869: item fetching failed at offset 511/512` → **probe failed -22**. No input device is created, so **keys don't work either**, not just the touchpad.
3. +10 s: `uhid_ready_disconn_timeout` → `HidHostService: Disabling HID connection for unsupported device` → **`HID_HOST policy 100 -> 0`**.

**Conclusion.** The Android 17 Bluetooth stack itself forbids the keyboard because the truncated descriptor is invalid. That's what happened at 13:49:20. The descriptor fix is therefore needed for *any* BLE input, and it must be applied **before** reconnecting. After applying it, the policy must be set back to 100.
