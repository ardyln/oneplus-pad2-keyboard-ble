# The touchpad over Bluetooth (and when it doesn't work)

**Status: open / inconclusive.** A user reported that with this module their keyboard's **keys work
over Bluetooth but the touchpad does not** (while docked on the pogo pins, the touchpad works fine).
This page records what that investigation found. The short version: on the reference unit the BLE
touchpad works and everything the module does is correct; on the reporter's unit the keyboard simply
never starts sending the touchpad over Bluetooth, for a reason that lives in the phone's Bluetooth
stack (or the keyboard's firmware), **not** in this module. The module- and app-level approaches tried
so far are ruled out (below), **but the root cause isn't pinned yet** and several leads are still open
— see [Open leads](#open-leads--help-wanted). If you hit this, the single most useful thing you can do
is capture an HCI log of a fresh pairing (method at the end) and open an issue. Until it's solved, the
touchpad works **docked**.

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

## What's ruled out, and what isn't

The decision to enable (or skip) the touchpad's CCCD is made inside the phone's Bluetooth stack
(`bta_hh_le` in `libbluetooth`), at bond time. That much is clear. What's been **tried and ruled out**:

- a module/descriptor change — the repair is already correct and identical to a working unit;
- an app writing the CCCD or re-injecting touch via uinput — Android blocks third-party GATT access to
  the HID service, so an app can't reach it (tested);
- a GATT-cache clear or reconnect — the CCCDs persist with the bond, so these don't re-issue them;
- "it's the Android version" — it fails on both Android 16 and 17.

What's **not** settled: *why* the host skips the touchpad CCCD on the affected unit (the extra report
tripping AOSP's report-array build is the leading guess, not a proven fact), and therefore whether a
targeted fix exists. So this is open, not closed.

## Open leads / help wanted

In rough order of effort vs. payoff:

1. **Capture a fresh-bond HCI log on the affected unit** — run [`tools/ble-touchpad-trace.sh`](../tools/ble-touchpad-trace.sh)
   (it gives the verdict on-device and saves the log) and open an issue. This is the decisive datum — it shows whether the touchpad CCCD `0x0034` is written at all, which separates
   "CCCD skipped" from "report not routed to uhid", and whether the extra report shifts the discovery.
   Nobody has run it yet on the affected unit; everything else is downstream of it.
2. **Isolate keyboard vs. ROM.** Try a *different* Pad 2 keyboard on the affected ROM, or the affected
   keyboard on a ROM where it's known to work. Works with a different keyboard → it's the keyboard's
   report layout; works on a different ROM → it's that ROM's `bluedroid`.
3. **If it's the report-array build:** read `bta_hh_le_process_cache_rpt` / `bta_hh_le_write_rpt_clt_cfg`
   in that ROM's `libbluetooth` and check how the extra report perturbs the per-device report table
   (it's built in cache order and the CCCD-write loop stops at the first unused slot). A one-line stack
   fix may well exist — worth a patch or an upstream report.
4. **ROM-side workarounds for a determined user:** a ROM where it works, a `bta_hh_le` patch, or (riskier,
   build-specific) replacing `libbluetooth` via a module. None of these are this module's job, but
   they're real paths, not dead ends.
5. **Not yet explored:** whether the keyboard can be made to present the reference report layout, and
   whether anything short of taking over the HCI transport can enable the CCCD from root. Both looked
   hard in passing; neither was actually attempted.

Meanwhile the touchpad works **docked (pogo)** — a separate kernel driver, unaffected by any of this.

## Diagnosing it on a device

Two read-only scripts in [`tools/`](../tools):

- **`bond-check.sh`** — is the keyboard a healthy encrypted **LE** bond? Catches the not-bonded
  ("pair with null") state and the classic/DUAL "Pair new device" trap.
- **`touchpad-test.sh`** — with the keyboard **detached** (on Bluetooth), finds the touchpad input
  node, runs a timed window, and counts the touch events while you swipe.
- **`ble-touchpad-trace.sh`** — captures an HCI log across a fresh pairing and reports, on-device,
  whether the touchpad's CCCD is enabled at bond (the decisive test; see below).

Read `touchpad-test.sh`'s output like this:

- `ABS_MT_POSITION > 0` → touch data is flowing; the keyboard and descriptor are fine. If there's
  still no cursor it's the ROM's pointer/gesture handling.
- `ABS_MT_POSITION = 0` (keys working, bond healthy) → the keyboard isn't sending the touchpad over
  Bluetooth on this unit — the case this page is about. Not fixable from the module.
- `resolution` is ~4 instead of 23 → the size swap didn't apply (pointer flies off-screen); the only
  module-side failure, fixed by a rebuild/reinstall.

### Capturing the proof (for a bug report)

Use [`tools/ble-touchpad-trace.sh`](../tools/ble-touchpad-trace.sh). It arms a clean capture, tells you
exactly what to tap, then checks the result **on the device** (no PC needed) and saves the logs. Push
it to the tablet and run its three steps in a **root** shell:

```
# step 1 -- start a clean capture; it prints the on-screen steps
sh ble-touchpad-trace.sh arm

#   now on the tablet SCREEN (no terminal output): Settings -> forget the keyboard ->
#   attach + detach it -> accept the pairing prompt -> press one or two keys, then stop.

sh ble-touchpad-trace.sh grab     # step 2 -- check + save
sh ble-touchpad-trace.sh off      # step 3 -- stop capturing
```

`grab` prints whether each keyboard report CCCD was enabled at bond, and the verdict:

- **touchpad `0x0034` = NO** while keys `0x0029` / consumer `0x002d` = yes → the stack skips the
  touchpad's notification at bond. **That's the bug.**
- **touchpad `0x0034` = yes** → the keyboard is told to send the touchpad; if it still doesn't work,
  the fault is downstream (report not routed to the input device).
- **all three = NO** → the capture missed the pairing (typed too much, or the bond didn't happen) —
  just run `arm` → re-pair → `grab` again.

It also saves `btsnoop_hci.log(.last).gz.b64` to `/sdcard` — attach those to the bug report.

**Why three steps:** the report CCCDs are written only at a **fresh bond** (a reconnect or cache clear
doesn't re-issue them), and the btsnoop log **rotates** under load so the pairing often lands in
`…log.last`; the script handles both.

**To analyse the saved log by hand** (on a PC with BlueZ) — the on-device check is a byte-level
heuristic, this is the authoritative view:

```
base64 -d btsnoop_hci.log.last.gz.b64 | gunzip > bond.btsnoop
btmon -r bond.btsnoop | grep -A3 'ATT: Write Request'
```

Look for writes to the report CCCDs (`0x0029`, `0x002d`, `0x0034`) with value `0100`; a missing
`0x0034` is the smoking gun.
