# The touchpad over Bluetooth (and when it doesn't work)

**Status: open / inconclusive.** A user reported that with this module their keyboard's **keys work
over Bluetooth but the touchpad does not** (while docked on the pogo pins, the touchpad works fine).
This page records what that investigation found. The short version: on the reference unit the BLE
touchpad works and everything the module does is correct; on the reporter's unit the keyboard simply
never starts sending the touchpad over Bluetooth, for a reason that lives in the phone's Bluetooth
stack (or the keyboard's firmware), **not** in this module — and that can't be fixed from a module or
an app. Use the touchpad **docked** there.

## How the BLE touchpad is supposed to work

Over Bluetooth the keyboard is a HID-over-GATT (HOGP) device. Its HID service (`0x1812`) exposes
several **Report** characteristics, one per HID report, each with a Client Characteristic
Configuration descriptor (**CCCD**, `0x2902`). For the host to receive a report, it must write `0100`
to that report's CCCD (enable notifications). The report map (the 563-byte descriptor this module
repairs) only describes the *shape* of the reports; the CCCDs are what actually turn the data on.

On the reference keyboard the HID service looks like this (value handles; the touchpad is report ID 3):

| Report characteristic (`0x2a4d`) | Report Reference | CCCD | Report |
|---|---|---|---|
| `0x0027` | `0x0028` → ID 1 | `0x0029` | keyboard |
| `0x002b` | `0x002c` → ID 1/consumer | `0x002d` | consumer control |
| `0x002f` | `0x0030` | — (output) | LEDs etc. |
| `0x0032` | `0x0033` → **ID 3** | **`0x0034`** | **touchpad** |

So "keys work, touchpad doesn't" means the host enabled the keyboard/consumer CCCDs but **not** the
touchpad's `0x0034`. The report map (which the module fixes) and the uhid device Android builds from it
are both fine — the touchpad input device exists with the right resolution — there just are no reports
flowing into it.

## What was checked, and what it ruled out

On the reporter's unit, all of the following were confirmed correct and identical to a working unit:

- the repaired **563-byte** report map (ends `…8103c0`), and the touchpad size swap (`resolution=23`);
- a healthy, **encrypted LE bond** (not the classic/"Pair new device" trap);
- Android's **touchpad input device** present and classified, with its gesture mapper active;
- the keyboard **firmware version** matched the reference unit.

And `getevent` on the touchpad node while swiping produced **zero** events over Bluetooth — the
touchpad reports never arrive — whereas the identical reference setup floods events.

Three fix ideas were tested and **ruled out**:

1. **A companion app writing the touchpad CCCD itself.** Not possible: Android reserves the HID GATT
   service (`0x1812`) for the system HID host and **blocks third-party GATT clients** from it
   (anti-keylogger). A test app connects and can read a non-HID characteristic (battery level, `status=0`)
   but every read/write to the HID service **stalls**. So neither "poke the CCCD" nor "subscribe and
   re-inject via uinput" is reachable from an app.
2. **Clearing the GATT cache to force re-discovery.** The report CCCDs are written **once, at bond
   time, and persist with the bond**. A reconnect — or even a full cache-clear + fresh service
   discovery — does **not** re-issue them. Confirmed with an HCI capture: on reconnect the host only
   re-writes the battery CCCD and the HID control point, never the report CCCDs.
3. **"It's Android 16."** The reporter later upgraded to Android 17 and the touchpad **still** failed,
   so the Android version is **not** the cause.

## What's proven vs. what's still open

**Proven (HCI btsnoop, decoded with `btmon`):** on the reference unit (Android 17), a *fresh bond*
writes `0100` to **all three** report CCCDs — `0x0029`, `0x002d`, and the touchpad's **`0x0034`**. So
the host is supposed to enable the touchpad notification at pairing, and does, on that unit.

**Open:** the two units differ in **two** ways at once, and they couldn't be separated:

- **Keyboard firmware.** The reporter's keyboard exposes an **extra Report characteristic** (one more
  than the reference unit — a feature report after the touchpad, with no CCCD). A keyboard's firmware
  doesn't change with the ROM, and this extra report is the one constant across *every* failure (both
  Android 16 and 17). AOSP's HID host builds its per-device report table sequentially and is sensitive
  to the exact set/order of report characteristics, so an extra report is a plausible trigger for the
  touchpad's CCCD never being written — on *any* ROM.
- **The ROM's Bluetooth stack.** The working unit runs one ROM, the reporter another; a different
  `bluedroid`/vendor HAL build can behave differently.

The one test that would separate them — an HCI snoop of a *fresh bond* on the reporter's unit, to see
whether `0x0034` is written — was not provided, and a keyboard swap wasn't possible. So the leading
explanation (the keyboard's report layout tripping AOSP's HID report handling) is **strongly indicated
but not proven**.

## Can it be fixed?

**Not from this module or any app, on any Android version.** The decision to enable (or skip) the
touchpad's CCCD is made inside the phone's Bluetooth stack (`bta_hh_le` in `libbluetooth`), which a
module can't touch cleanly or portably, and the HID GATT service is walled off from apps. The realistic
options:

- **Use the touchpad docked (pogo).** Works regardless — it's a separate kernel driver, not HOGP.
- **A different keyboard unit** (one without the extra report, like the reference unit) would likely
  work, *if* the cause is the keyboard's report layout. A keyboard's firmware can't be changed on a
  custom ROM.
- **A fixed Bluetooth stack** — a ROM where it works, or a `bta_hh_le` fix from the ROM/AOSP
  maintainers (the HCI capture above makes a precise bug report possible).

## Diagnosing it on a device

Two read-only scripts in [`tools/`](../tools):

- **`bond-check.sh`** — is the keyboard a healthy encrypted **LE** bond? Catches the not-bonded
  ("pair with null") state and the classic/DUAL "Pair new device" trap.
- **`touchpad-test.sh`** — with the keyboard **detached** (on Bluetooth), finds the touchpad input
  node, runs a timed window, and counts the touch events while you swipe.

Read `touchpad-test.sh`'s output like this:

- `ABS_MT_POSITION > 0` → touch data is flowing; the keyboard and descriptor are fine. If there's
  still no cursor it's the ROM's pointer/gesture handling.
- `ABS_MT_POSITION = 0` (keys working, bond healthy) → the keyboard isn't sending the touchpad over
  Bluetooth on this unit — the case this page is about. Not fixable from the module.
- `resolution` is ~4 instead of 23 → the size swap didn't apply (pointer flies off-screen); the only
  module-side failure, fixed by a rebuild/reinstall.

### Capturing the proof (for a bug report)

The report CCCDs are only written at a *fresh bond*, and the btsnoop log rotates under load, so:

```
# 1. arm (root)
setprop persist.bluetooth.btsnooplogmode full
cmd bluetooth_manager disable; cmd bluetooth_manager wait-for-state:STATE_OFF
rm -f /data/misc/bluetooth/logs/btsnoop_hci.log*
cmd bluetooth_manager enable; cmd bluetooth_manager wait-for-state:STATE_ON
# 2. forget the keyboard, attach+detach, accept the pairing prompt, press a key or two, then stop
# 3. grab BOTH logs (the pairing may be in .last after rotation)
cat /data/misc/bluetooth/logs/btsnoop_hci.log.last 2>/dev/null | gzip -c | base64   # and btsnoop_hci.log
# 4. off
setprop persist.bluetooth.btsnooplogmode disabled; cmd bluetooth_manager disable; cmd bluetooth_manager enable
```

Decode on a PC with `btmon -r <file>` and look for `ATT: Write Request` to the report CCCDs
(`0x0029`, `0x002d`, `0x0034`) with value `0100`. A missing `0x0034` is the smoking gun.
