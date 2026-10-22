# ROMs that handle the keyboard themselves (PixelOS 17 for caihong, 2026-10-22 builds)

On 2026-10-22, inferno0230 (the `caihong` maintainer) added an app to his ROM that pairs the
Smart Keyboard over Bluetooth when it's detached. This page records what that ROM does and doesn't
cover, measured on two builds from that day, and why module v0.12 switches to a latency-only mode on
such ROMs. All times are the tablet's local time (UTC+03:00) unless marked UTC.

## The builds

Both builds are PixelOS 17 by inferno0230. The build fingerprint is the stock OnePlus one and is the
same on both, so it doesn't identify the build; use `ro.custom.build.date` or `ro.build.date.utc`.

| Property | Build 1 | Build 2 |
|---|---|---|
| `ro.custom.build.date` | **`20261022-1057`** | **`20261022-1226`** |
| `ro.build.date` | Thu Oct 22 16:27:44 IST 2026 (10:57:44 UTC) | Thu Oct 22 17:56:52 IST 2026 (12:26:52 UTC) |
| `ro.build.date.utc` = `ro.build.version.incremental` | `1792666664` | `1792672012` |
| Touchpad over Bluetooth | ~6× too fast | normal speed |

Same on both builds:

| Property | Value |
|---|---|
| `ro.build.display.id` | `CP2A.260605.016` |
| `ro.build.flavor` | `custom_caihong-userdebug` (`ro.build.type` = `user`) |
| `ro.build.user` / `ro.build.host` | `inferno0230` / `archlinux` |
| Android | 17 (SDK 37), security patch `2026-10-01`, `net.pixelos.version` = `seventeen` |
| Kernel | `6.1.174-g638ecc425319` |
| `ro.build.fingerprint` (stock, spoofed) | `OnePlus/OPD2403IN/OP5DAAL1:16/UKQ1.231108.001/U.R4T3.31362f8-b6a7dc-bdc05c:user/release-keys` |
| Keyboard app | `OplusKeyboard` (`org.lineageos.keyboard`), `/system_ext/priv-app/OplusKeyboard/OplusKeyboard.apk`, sha256 `e87272d7d8d67959322aece8a38261451675f50455db54a1948efd2142e83ad4` (byte-identical in both builds) |
| Its source | [inferno0230/android_hardware_oplus@`9fcccd5d073391702500a41b5061b16bc9c86819`](https://github.com/inferno0230/android_hardware_oplus/commit/9fcccd5d073391702500a41b5061b16bc9c86819) "packages: Introduce OplusKeyboard" (2026-10-22 11:49 UTC), `packages/Keyboard/` |

Build 2 only:

| File | sha256 |
|---|---|
| `/odm/usr/idc/Vendor_22d9_Product_3869.idc` (adds `touchpad.resolution.*`, below) | `3ddc48fd70ad02a6258de875cf432176bf6c2ec1953989eaffdb954902527994` |
| `/system/lib64/libinputflinger.so` (reads those keys) | `cd1620c7098b8d37c7e642c0d9706ff0f5d5e57efbcc6b35974af77392475482` |

Hardware: OnePlus Pad 2 (OPD2403, `caihong`), KernelSU (ksud 3.3.1), keyboard "OnePlus Pad Smart
Keyboard" (22D9:3869, firmware version `0x0111`). The module was not installed during the
measurements below (it was uninstalled at 15:40, before build 1's tests) until v0.12 was tested at 17:06.

## What `OplusKeyboard` does

From the APK in the build (decompiled with jadx); the source is the commit above. It's a
boot-started service:

- It listens for the pogo driver's uevent (`DEVPATH=/devices/virtual/pogopin/pogo_keyboard`,
  `pogopin_status` = 1/0) and takes the keyboard's address from the same uevent (`mac_addr`).
- **Detached:** if the keyboard isn't paired, it scans for that address (60 s) and calls
  `createBond(TRANSPORT_LE)`. If it is, it sets the HID host connection policy to *allowed*.
- **Attached:** it sets the policy to *forbidden*, so keys don't arrive twice.

That covers pairing and double input. It doesn't touch the report map or the connection interval.

## Finding 1: the whole report map is read (both builds)

The keyboard's report map is 563 bytes. On the ROMs this module was written for, Android kept only the
first 512 and the kernel rejected the map. On build 1, a fresh pairing at 15:42:47 shows the stack
reading all of it (HCI snoop, `tools/btsnoop_kbd.py LOG <address prefix> read 0x001e`):

```
15:42:50.955 tablet reads 0x001e (Report Map) at offset 0  -> 516 bytes (the first 512 are kept)
15:42:51.463 tablet reads 0x001e at offset 512             -> 51 bytes  (…01810295078103c0)
15:42:51.597 tablet reads 0x001e at offset 563             -> 0 bytes   (end)
```

The map stored in `bt_config.conf` afterwards is these 563 bytes, byte for byte. So the module's
map repair isn't needed on this ROM. This snoop doesn't show whether the full read comes from the
ROM's Bluetooth stack or from AOSP itself.

The two connections just before this pairing (15:41:59 and 15:42:25) used the old pairing and were
dropped by the tablet (reason 0x16) about 11-14 s after connecting. The module's uninstall at 15:40
had cut the stored map back to 512 bytes, because the ROM's full map ends with the same 51 bytes
the module appends. That is very likely why. v0.12 no longer touches the map on such ROMs, including
at uninstall.

## Finding 2: touchpad speed (fixed in build 2)

The firmware declares the touchpad as 70 × 41 cm (Physical Max = Logical Max, 2764 × 1630 in units
of 0.01 inch). The real pad is about 120 × 71 mm. So the kernel reports **4 units/mm** instead of
23, on both builds; the map isn't changed by the ROM.

- **Build 1:** the pointer moves about 6× too fast (its IDC file wasn't saved, so its contents
  aren't recorded here).
- **Build 2:** the IDC file adds
  ```
  # The touchpad reports 4 units/mm over Bluetooth
  touchpad.resolution.x = 23
  touchpad.resolution.y = 23
  ```
  and the ROM's `libinputflinger.so` reads those keys (the strings are in the library) and hands 23
  to the touchpad gesture code. The pointer moves at normal speed. AOSP itself has no such keys: its
  `HardwareProperties.cpp` (main, checked 2026-10-22) takes the resolution only from the kernel, and
  `gestureProp.*` IDC entries can't set it. So this is a ROM patch.

Note: `dumpsys input` still prints `resolution=4` under "Axis info" on build 2. That line is the
kernel's value, not what the gesture code uses, so it can't tell whether the fix is active. The
IDC file and the pointer speed can. The file matches the keyboard's vendor and product IDs, so it
also applies when docked, where the pogo touchpad already reports 23.

## Finding 3: the Bluetooth interval drops to 45 ms after every reboot

The keyboard publishes its preferred connection parameters (GAP, handle `0x0007`):
`06 00 06 00 19 00 f4 01`, which is **7.5 ms min and max, latency 25, 5 s timeout**.

On every connection, Android first sets 30–50 ms (the link lands on 45 ms). It switches to the
keyboard's 7.5 ms only if it has read those parameters since the last reboot, which happens during
a pairing. After a reboot it doesn't read them again, so every connection stays at 45 ms until the
keyboard is forgotten and paired again.

At 45 ms the touchpad still sends 80–120 reports a second, but they arrive in bunches of about 5
every 45 ms. That adds up to ~45 ms of lag and can feel choppy. At 7.5 ms they arrive one at a time.

Build 2, measured with `tools/btsnoop_kbd.py` (`timeline` and `delivery`):

| Time | Situation | Interval | Touchpad delivery |
|---|---|---|---|
| 16:37:08 | First connection after boot | 45 ms | ~4.6 per bunch, every 45 ms |
| 16:45:54 | After a detach (same boot) | 45 ms | ~5.4 per bunch, every 45 ms |
| 16:49:58 | After forgetting and pairing again | **7.5 ms**, latency 25 | 1.2 at a time, every 7.6 ms |
| 16:51:21 | Detach again (same boot) | **7.5 ms**, latency 25, without re-reading | 1.1 at a time, every 7.6 ms |
| 16:52:30 | First connection after a reboot | 45 ms | ~4.7 per bunch, every 45 ms |

The pairing and the next detach (build 2):
```
16:49:58.870 connected at 15.0 ms
16:50:02.364 TABLET asks 30.0-50.0 ms, latency 0
16:50:02.579 interval now 45.0 ms
16:50:02.982 TABLET asks 7.5-11.25 ms, latency 25      <- the keyboard's preferred parameters
16:50:03.480 interval now 7.5 ms, latency 25
16:51:21.332 connected at 15.0 ms                      (detach, same boot)
16:51:21.381 TABLET asks 30.0-50.0 ms, latency 0
16:51:21.734 interval now 45.0 ms
16:51:21.826 TABLET asks 7.5-11.25 ms, latency 25      <- no new read of 0x0007
16:51:22.367 interval now 7.5 ms, latency 25
```

Build 1 behaves the same: after its fresh pairing at 15:42:47, every connection that boot got 7.5 ms
(15:42:51, 15:43:33, 15:45:04, 15:50:49). The one 45 ms connection was before the pairing
(15:42:25). Once, at 15:41:59, the keyboard itself asked for 7.5 ms (an LL connection parameter
request) and got it. That didn't happen again in any later connection, so it can't be relied on.

### Why: this is AOSP's own behaviour

In AOSP's HID-over-GATT host (`system/bta/hh/bta_hh_le.cc`, main, checked 2026-10-22), the
keyboard's preferred parameters are read in exactly one place: `bta_hh_le_srvc_search_cmpl`, at the
end of a service discovery, which calls `read_pref_conn_params_cb`. That callback raises a maximum
below 11.25 ms to 11.25 ms (`L2CA_AdjustConnectionIntervals`, `BTM_BLE_CONN_INT_MIN_LIMIT` = 9),
which gives the **7.5–11.25 ms, latency 25** seen in the snoops. It stores the values with
`BTM_BleSetPrefConnParams` and requests them.

A paired keyboard doesn't get a service discovery when it reconnects: `bta_hh_security_cmpl` loads
the cached reports (`HidReport` in `bt_config.conf`) and skips discovery ("Cache found, no need to
perform service discovery"). The values stored by `BTM_BleSetPrefConnParams` live in the in-memory
device record (`p_dev_rec->conn_params`), which isn't saved with the pairing. So reconnects in the
same boot get 7.5 ms, and after a reboot nothing reads the parameters again. This ROM runs that
code unchanged as far as the snoops show, so it applies to any ROM.

Before this ROM, the module's companion app requested Android's high-priority interval on every
connection, so reboots didn't matter as much (15 ms instead of 7.5 ms).

## Module v0.12 on these ROMs

The module looks for the app's default-permissions file
(`/system_ext/etc/default-permissions/default-permissions_org.lineageos.keyboard.xml`, or the same
under `/product`, `/system`, `/vendor`, `/odm`). That file is there from early boot, before the
package manager runs. `ROM_NATIVE` in `config.sh` can force the mode (`yes`/`no`; default `auto`).
If the file is there, the module:

- doesn't edit the report map, at boot or at uninstall, and never restarts Bluetooth;
- doesn't pair the keyboard or change the HID policy (`OplusKeyboard` does both), at uninstall
  either (the ROM forbids HID while the keyboard is docked);
- on each detach runs `HidCtl tune` (below) and starts the latency helper; both stop on attach;
- logs, and shows under the Action button, whether the ROM sets the touchpad resolution.

The connection-interval part runs in both modes (it also helps on ROMs without `OplusKeyboard`):

- **`HidCtl tune`** (root, via `app_process`) waits for the keyboard to be paired and connected,
  reads its preferred parameters itself (the GAP service isn't walled off like the HID service), and
  after 3 s, if the link is slower than the keyboard's maximum, requests them with the same
  adjustment Android makes, through the hidden `BluetoothGatt.requestLeConnectionUpdate`. That call
  is hidden from apps (an app gets `NoSuchMethodException`), which is why it runs as root. The link
  keeps the parameters after this client closes. In effect it does on every detach what Android
  does only at pairing.
- **The latency helper** (the app) is the fallback: it watches the link's interval (Android reports
  every change to every GATT client on the link) and, 6 s after connecting, requests Android's
  high-priority interval (11.25–15 ms) only if the link is still slower than 15 ms. It also covers
  reconnects between detaches.

A map that an older module version (v0.11 or earlier, run on such a ROM) already edited keeps its
touchpad size correction. That's harmless: it gives the same 23 units/mm the ROM's IDC file sets,
and on a build without that IDC fix (like `20261022-1057`) it's what makes the speed right.

### Tests on build 2 (2026-10-22)

| Time | Module | Situation | Interval | Touchpad delivery |
|---|---|---|---|---|
| 17:11:54 | high priority only | Detach after the 17:06 reboot | 45 ms → 15 ms | |
| 17:13:06 | high priority only | First detach after the 17:13 reboot | 45 ms → 15 ms | 1.8 per delivery, every 15 ms |
| 17:15:55 | high priority only | Forgotten and paired again; the helper waited for the pairing (bond state 11 at the detach) | **7.5 ms** (Android); the helper logged `BLE interval already 7.5 ms; not requesting high priority` | 1.2 per delivery, every 7.6 ms |
| 17:28:57 | with `HidCtl tune` | Keyboard detached through the 17:28 reboot | 45 ms → **7.5 ms**, latency 25 (`hidctl tune: rc=0 tune: interval now 7.5 ms, latency 25`); the helper logged `already 7.5 ms` | 1.5 per delivery, every 7.7 ms; 116 reports/s while moving |

```
17:28:07.992 interval now 45.0 ms                      (connection made at boot)
17:28:57.302 TABLET asks 7.5-11.25 ms, latency 25      <- HidCtl tune, the keyboard's own parameters
17:28:57.768 interval now 7.5 ms, latency 25
```

Uninstall on build 2 left the stored report map byte-identical (same 563 bytes), removed the app,
its whitelist entry and the module's state, and didn't touch the HID policy.

## Open leads

- **Fix the reboot loss in AOSP.** `bta_hh_security_cmpl` could still read the GAP preferred
  parameters when it uses the cached reports (one characteristic read), or the parameters could be
  saved with the pairing like the reports are. Either would give every HOGP device its preferred
  interval after a reboot, with no module. The analysis above is the basis for a bug report.
- **`OplusKeyboard` could do what `HidCtl tune` does.** It's built with `certificate: "platform"`
  and `platform_apis: true` (its `Android.bp`), so it can call `requestLeConnectionUpdate`
  directly: after connecting on detach, read GAP `0x2a04` and request those parameters. That would
  cover this ROM without the module.
## How to reproduce

1. Developer options → Enable Bluetooth HCI snoop log → **Enabled** (full), then toggle Bluetooth.
2. Do the connection you want to see (reboot, detach, forget + pair), move a finger on the touchpad
   for ~10 s.
3. Pull both logs (the stack rotates them):
   `adb shell su -c 'cat /data/misc/bluetooth/logs/btsnoop_hci.log' > snoop.log` (same for `.log.last`).
4. On a PC: `python3 -I tools/btsnoop_kbd.py snoop.log <first 3 bytes of the keyboard address> timeline`
   (or `delivery`, or `read 0x001e` / `read 0x0007`).
