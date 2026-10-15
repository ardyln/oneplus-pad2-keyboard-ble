# ANALYSIS — Drun555 "OnePlus Pad 3 Keyboard BLE" KernelSU module v1.7

Analysis of the Pad 3 module, written for porting it to the OnePlus Pad 2 (`caihong`). The upstream repo has no license file; its author has been contacted about this port.

## Sources examined

| Source | Location here | SHA-256 |
|---|---|---|
| Release zip `OnePlus_Pad3_Keyboard_BLE_KSU-v1.7.zip` | `Desktop/`, extracted to `pad3_module/release_v1.7/` | `eab5e7cc…8697` |
| GitHub source archive (`main`, commit `033c11e9`) | `pad3_module/oneplus-pad3-keyboard-ble-main/` | — |
| Copy pulled from the tablet (`/data/adb/modules/oneplus_pogo_keyboard_ble`) | `pad3_module/installed_v1.7/` | identical to the release |
| Disassembly of `PogoPair.apk` / `hidctl.jar` (baksmali; jadx not installed) | `pad3_module/decompiled/` | APK `32dbf5fd…bd1b5`, jar `6552bdc8…608a` |

**The binaries match the source.** The smali has exactly the same string constants, classes and invoked framework methods as `PogoPair/src` and `HidCtl/src`. There's no extra code, no `java.net`/socket/HTTP, no file I/O, no `Runtime.exec`. The APK is signed with a self-made debug key (`CN=Android Debug, O=Codex`), versionName 1.3, targetSdk 28, compileSdk 35.

Module files:

```
module.prop  post-fs-data.sh  service.sh  uevent-handler.sh  switch-mode.sh  action.sh  descriptor-fix.sh
hidctl.jar   PogoPair.apk
system/priv-app/PogoPair/PogoPair.apk
system/etc/permissions/privapp-permissions-pogopair.xml   (grants BLUETOOTH_PRIVILEGED)
```
There is **no `uninstall.sh`** and no `customize.sh`.

## 1. Boot flow

1. **`post-fs-data.sh`** runs `descriptor-fix.sh apply` early in boot, before the Bluetooth stack starts.
2. **`service.sh`** waits for `sys.boot_completed=1` and `sys.user.0.ce_available=true`. It then does the following:
   - `pm install -r -g PogoPair.apk` if `local.codex.pogopair` isn't installed (`service.sh:16-18`). The comment says KernelSU on the author's ROM doesn't mount `system/`, so the priv-app copy and the privapp-permissions XML are effectively unused, and the app ends up as an **ordinary user app in `/data/app`**.
   - `cmd deviceidle whitelist +local.codex.pogopair` (`:22`), so its background service can start.
   - `settings put global hidden_api_policy{,_p_apps,_pre_p_apps} 1` (`:23-25`). **This is a system-wide change.**
   - Starts `busybox uevent uevent-handler.sh &` (`:29`).
   - Runs an endless loop every 3 s (`:33-53`):
     - It sets `MODE=1` if `dumpsys input` contains `pogo_touchpad`, otherwise `MODE=0`. On a change it calls `switch-mode.sh attached|detached`.
     - If `descriptor-fix.sh check` says the descriptor needs fixing, it turns **Bluetooth off**, applies the fix, and turns Bluetooth back on.

## 2. Pairing trigger

- The trigger is the detach transition, which calls `switch-mode.sh detached` (`switch-mode.sh:16-25`). That does two things:
  1. `app_process … HidCtl resume MAC`, explained in section 4.
  2. `am broadcast -a local.codex.pogopair.PAIR -n local.codex.pogopair/.PairReceiver --es mac MAC`.
- **`PairReceiver.onReceive`** (`PairReceiver.java:18-61`) does the following:
  - It takes the MAC from `EXTRA_DEVICE` or from the `mac` extra, defaulting to `DEFAULT_MAC`. It **ignores any MAC other than the hardcoded one** (`:22`), so passing a different MAC in the extra has no effect.
  - If the device is already `BOND_BONDED`, it starts `LatencyService` with that MAC.
  - If it's `BOND_BONDING`, it does nothing.
  - Otherwise it calls `cancelDiscovery()`, then `createBond(TRANSPORT_LE=2)` by reflection (a hidden API). If that throws, it falls back to the public `createBond()`.
- No scan is performed. `createBond` on a known LE address makes the stack page or connect directly. This only works while the keyboard is advertising, which on the Pad 3 is right after a physical detach.
- `MainActivity` (launcher icon "Pogo BLE Pair") is a manual fallback. It does the same `createBond(LE)` with the `mac` extra or the default MAC, and shows the bond state. It also calls `adapter.enable()` if Bluetooth is off.
- The manifest also listens for `BOND_STATE_CHANGED`. That's an implicit broadcast with no manifest-receiver exemption, so on API 26+ it's very likely never delivered. I treat it as inert.

## 3. Attach/detach state machine

There are two inputs. Both call the same idempotent `switch-mode.sh`, so each transition usually runs twice.

| Source | Detects | Where |
|---|---|---|
| Kernel uevent, via `busybox uevent` | `DEVNAME=pogo_keyboard` with `pogopin_status=1` (attached) or `0` (detached) | `uevent-handler.sh:3-14` |
| 3 s poll | input device whose name contains `pogo_touchpad` (attached) | `service.sh:34-44`, `action.sh:5` |

| Mode | Actions (`switch-mode.sh`) |
|---|---|
| **attached** | `am stopservice LatencyService`, then `HidCtl suspend MAC`: HID-host connection policy set to **FORBIDDEN (0)**, then `disconnect(device)`. This prevents double input. |
| **detached** | `HidCtl resume MAC`: policy set to **ALLOWED (100)**, then `connect(device)`. Then the `PAIR` broadcast, which bonds or starts `LatencyService`. |

At boot, the first loop iteration always fires one transition. If the keyboard isn't attached, that's "detached", so every boot triggers a resume, connect and bond attempt.

`action.sh` (the KernelSU "Action" button) re-runs the mode that matches the current `dumpsys input` state.

## 4. Hidden and system APIs used

**`hidctl.jar`** runs as **root** via `CLASSPATH=hidctl.jar app_process /system/bin local.codex.pogopair.HidCtl suspend|resume MAC`, with a 7 s watchdog `System.exit(3)`.

| API | Kind |
|---|---|
| `ActivityThread.systemMain()` / `getSystemContext()` | hidden |
| `android.os.BluetoothServiceManager` constructor + `BluetoothFrameworkInitializer.setBluetoothServiceManager()` | hidden / module-SystemApi |
| `android.os.ServiceManager.getService("bluetooth_manager")` | hidden |
| `IBluetoothManager.Stub.asInterface()` | hidden AIDL |
| `BluetoothAdapter(IBluetoothManager, Context)` private constructor, via `setAccessible(true)` | private |
| `BluetoothHidHost.setConnectionPolicy(device, 0/100)` | SystemApi (BLUETOOTH_PRIVILEGED) |
| `BluetoothHidHost.connect()` / `disconnect()` | hidden/SystemApi |

Exit codes: 0 = ok, 2 = usage, 3 = timeout, 4 = both calls false, 5 = exception, 6 = `getProfileProxy` false. `switch-mode.sh` discards all output, so failures are invisible apart from logcat tag `PogoPair`.

**`PogoPair.apk`** runs as an untrusted user app.

| API | Kind |
|---|---|
| `BluetoothDevice.createBond(int transport)` by reflection | hidden (`@UnsupportedAppUsage`) |
| `BluetoothHidHost.disconnect(device)` by reflection, in `PairReceiver.disconnectHid` (`ATTACH` action only) | hidden/SystemApi |
| `BluetoothGatt.requestConnectionPriority(HIGH)` | public |

The global `hidden_api_policy=1` exists so that these reflective calls aren't blocked for the user app. Plain `app_process` started from a shell doesn't enforce the hidden-API denylist anyway.

**Touchpad latency.** `LatencyService` is a sticky service. It opens a second GATT client (`connectGatt(autoConnect=false, TRANSPORT_LE)`) to the bonded keyboard. On connect it calls `requestConnectionPriority(CONNECTION_PRIORITY_HIGH)` (11.25–15 ms interval) immediately and again after 2 s. It reconnects every 1.5 s on disconnect until it's stopped.

## 5. Descriptor patch logic (`descriptor-fix.sh`)

- **Problem.** BLE GATT attribute values are limited to 512 bytes. The keyboard's Report Map is 561 bytes, and Fluoride/Gabeldorsche stores only the first 512 in `bt_config.conf` as `HogpDescriptor` (hex, 1024 chars). That cuts off the touchpad collection.
- **`check`** looks in `/data/misc/bluedroid/bt_config.conf` for a section `[XX:XX:XX:XX:XX:XX]` that has `HogpVendorId = 8921`, `HogpProductId = 14441`, and a `HogpDescriptor` that is 1024, 1208 or 1210 hex chars long (512, 604 or 605 bytes). The 604/605 lengths appear to repair older broken patches from earlier module versions.
- **`apply`** keeps the first 1024 hex chars and appends a fixed 98-hex-char (49-byte) `TAIL`, giving 1122 hex chars (561 bytes). Its length no longer matches, so the fix doesn't loop. The tail continues a touchpad collection that is already in progress at byte 512: 29-byte report, five 5-byte contacts, 16-bit scan time, contact count, button, and the closing `c0`. The file is rewritten through a temp file `.bt_config.pogofix` with `cat > CFG`, then `chown bluetooth:bluetooth`, `chmod 0660` and `chcon bluetooth_data_file`.
- **Runtime path.** For a new bond, `service.sh` detects the 512-byte map within 3 s and restarts Bluetooth so UHID re-creates the device with the 561-byte map.
- **No backup** of `bt_config.conf` is made.

## 6. Every hardcoded device-specific value

| Value | File:line, or class.method |
|---|---|
| MAC `XX:XX:XX:XX:XX:XX` | `switch-mode.sh:4`; `descriptor-fix.sh:17,34` (lower-case section match); `PairReceiver.DEFAULT_MAC` (`PairReceiver.java:15`, used and **enforced** at `:21-22` in `onReceive`); `LatencyService.DEFAULT_MAC` (`LatencyService.java:18`, field init `:21`); `MainActivity.onCreate` (`MainActivity.java:40`). Smali: `PairReceiver.smali`, `LatencyService.smali`, `MainActivity.smali` |
| VID `8921` (0x22D9, OnePlus) | `descriptor-fix.sh:18,35` |
| PID `14441` (0x3869) | `descriptor-fix.sh:19,36` |
| Truncated lengths `1024/1208/1210` hex | `descriptor-fix.sh:22,39` |
| Descriptor `TAIL` (49 bytes) | `descriptor-fix.sh:10` |
| uevent `DEVNAME=pogo_keyboard` | `uevent-handler.sh:3` |
| uevent var `pogopin_status` 0/1 | `uevent-handler.sh:7-13` |
| Input device name `pogo_touchpad` | `service.sh:36`, `action.sh:5` |
| busybox `/data/adb/ksu/bin/busybox` | `service.sh:4`, `descriptor-fix.sh:3` |
| Config path `/data/misc/bluedroid/bt_config.conf` | `descriptor-fix.sh:4` |
| Package/component `local.codex.pogopair/.PairReceiver`, `.LatencyService` | `switch-mode.sh:11,23`, manifest |
| HID_HOST profile id `4`, TRANSPORT_LE `2`, policy `0`/`100` | `HidCtl.java:57,74`; `PairReceiver.java:52,82`; `MainActivity.java:52` |
| Poll period 3 s; GATT retry 1.5 s / 2 s; HidCtl timeout 7 s | `service.sh:52`; `LatencyService.java:29,31,46`; `HidCtl.java:51` |
| Model in description `OPD2415` | `module.prop:6` |

## 7. Risky or surprising behaviour

1. **System-wide hidden-API policy.** `hidden_api_policy*=1` is set on every boot and **never reverted** (there's no `uninstall.sh`). It lets every app use hidden APIs. **It's still set on this tablet now** from the earlier test install, even though the module is disabled.
2. **Persistent leftovers on uninstall.** The user-app install of `local.codex.pogopair` and its deviceidle whitelist entry both survive disabling or removal. **Both are present on this tablet now** (installed 2026-10-12 13:51, whitelisted). The HID connection policy can also be left at FORBIDDEN if the keyboard was attached at removal time.
3. **Automatic Bluetooth restarts.** The loop toggles Bluetooth off and on whenever `check` matches. That disconnects all BT devices, including headphones and the stylus, without asking. If `apply` failed (for example, busybox missing), it would restart Bluetooth every ~3 s indefinitely.
4. **`bt_config.conf` written in place with no backup**, both at post-fs-data and at runtime while Bluetooth is off. This file also holds link keys for every bonded device. A truncated write would unpair everything.
5. **Exported, unprotected components.** Any app can broadcast `local.codex.pogopair.ATTACH` to force a HID disconnect, or start the exported `LatencyService` with an arbitrary `mac` extra to hold a GATT link to any bonded device. Impact is low but non-zero.
6. **Silent failures.** All `am`, `app_process` and `pm` output goes to `/dev/null`, and there's no log file.
7. **Bond attempt on every boot** while detached, even if the keyboard is far away. It's harmless but noisy.
8. **No network access, no writes** outside `bt_config.conf`, `settings`, the package manager and the deviceidle whitelist, and no partition or `setprop` changes. That's good.
9. `module.prop` says `author=Codex`. The code appears to be AI-generated for Drun555. That doesn't make it unsafe; it's just context.
