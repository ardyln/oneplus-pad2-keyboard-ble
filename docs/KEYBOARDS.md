# OnePlus / OPPO tablet keyboards: names, IDs, touchpads

Findings from 2026-10-16, collected while writing a Linux hwdb entry for the Pad 2 keyboard
([`linux/61-oneplus-pad-keyboard.hwdb`](../linux/61-oneplus-pad-keyboard.hwdb)). They explain why that
entry matches the keyboard by **name** and not by its Bluetooth vendor/product ID.

## Short version
- The Pad 2 keyboard reports ID **22d9:3869** (vendor 0x22D9, OPPO). The Pad 3 keyboard reports the same
  ID, and OnePlus' pogo keyboard driver uses 0x3869 as its default product ID for other models too.
- Each keyboard model announces its **own Bluetooth name**. The Pad 2 keyboard calls itself
  **"OnePlus Pad Smart Keyboard"**, although the box says "OnePlus Pad 2 Smart Keyboard".
- "OnePlus Pad 2 Smart Keyboard" *is* a Bluetooth name, but of a different keyboard: the one for
  China's MediaTek "OnePlus Pad 2" (一加平板2, 2025), whose touchpad needs a different resolution.
- So an ID match can't tell the models apart, while a name match can.

## Bluetooth names and touchpads, from OnePlus' device trees
OnePlus' pogo keyboard driver (`tinno,pogo_keyboard`) reads each tablet's keyboard names and touchpad
values from the device tree: `keyboard-ble-name-strings`, `id-product`, `touchpad-xy-max` and
`touchpad-xy-resolution` (see [`pogo_keyboard_core.c`][drv]). Each tablet lists three names, picked by a
brand index: OPPO, OnePlus China, OnePlus global (the order is inferred from the driver's fallback names
and from the Pad 2, whose third name is what the global keyboard announces).

| Tablet (codename, chip) | Bluetooth names (OPPO / OnePlus China / OnePlus global) | Touchpad max | Resolution (units/mm) | `id-product` |
|---|---|---|---|---|
| `caihong`, Snapdragon 8 Gen 3 ([dtsi][caihong]) | OPPO Pad 3 Pro Keyboard / OnePlus Pad Pro Keyboard / **OnePlus Pad Smart Keyboard** | 2764 × 1630 | 23 × 23 | not set (default 0x3869) |
| `erhai`, Snapdragon 8 Elite ([dtsi][erhai]) | OPLUS Pad 4 Pro Keyboard / OnePlus Pad 2 Pro Keyboard / OnePlus Pad 3 Keyboard | 2764 × 1630 | 23 × 23 | not set (default 0x3869) |
| `iceland` ([dtsi][iceland]) | OPPO Pad 5 Pro Smart Keyboard / OnePlus Pad 3 Pro Smart Keyboard / OnePlus Pad 4 Smart Keyboard | 2560 × 1440 | 24 × 25 | not set (default 0x3869) |
| MediaTek mt6991 ([dtsi][mt6991]) | OPPO Pad 5 Smart Keyboard / OnePlus Pad 2 Smart Keyboard / OnePlus Pad 2 Smart Keyboard | 2764 × 1630 | 26 × 26 | not set (default 0x3869) |
| MediaTek mt6897 ([dtsi][mt6897]) | OPLUS Pad 3 Smart Keyboard / OnePlus Pad Keyboard / OnePlus Pad 3R Smart Keyboard | not set | not set | **0x3868** |

The `id-product` default applies to the input devices the driver creates on the pogo connection. The
Bluetooth ID of each keyboard comes from its own firmware; only the Pad 2's (22d9:3869, read on the tablet
and on Linux) and the Pad 3's (same, per the Pad 3 module this one is ported from) are known.

## Store names
Store names differ from the Bluetooth names, and the model numbers shift by one generation between China
and the rest of the world. Matched to the tablets by name and launch date, not by official spec sheets.

| Tablet | Global | China | OPPO |
|---|---|---|---|
| `caihong` | OnePlus Pad 2 Smart Keyboard (OPK2402), for the OnePlus Pad 2 | 一加平板 Pro 智能触控键盘 | OPPO Pad 3 Pro 智能触控键盘 |
| `erhai` | OnePlus Pad 3 Smart Keyboard, for the OnePlus Pad 3 | 一加平板 2 Pro 智能触控键盘 | OPPO Pad 4 Pro 智能触控键盘 |
| mt6991 | (none found) | 一加平板 2 智能触控键盘, for 一加平板2 (Dimensity 9400+, Oct 2025) | OPPO Pad 5 智能触控键盘 |
| `iceland` | OnePlus Pad 4 Smart Keyboard | 一加平板 3 Pro 悬浮键盘 | OPPO Pad 5 Pro 悬浮键盘 |

Sources: [OnePlus tablets on OPPO China][oppo-op], [OPPO tablets on OPPO China][oppo-tab],
[OPK2402 listing][opk2402], [一加平板2 launch (Gamersky)][gamersky], [OnePlus Pad 4 keyboard listing][pad4].

## The Pad 2 keyboard on Linux
Tested over Bluetooth on Ubuntu 26.10 (GNOME, Wayland). Linux reads the whole HID report map
(**563 bytes**; Android stops at 512, which is what the module repairs) and creates three input devices:
`OnePlus Pad Smart Keyboard`, `… Consumer Control` and `… Touchpad`.

| Key | What it sends | Without a fix | hwdb fix |
|---|---|---|---|
| Esc | Consumer AC Back (0x0c0224) | Back, does nothing | `esc` |
| Microphone | Keyboard F13 (0x070068) | GNOME opens Settings | `micmute` |
| Search | Keyboard F23 (0x070072) | nothing | `search` |
| Lock | Keyboard F24 (0x070073) | nothing | `screenlock`, as systemd maps other lock keys; GNOME doesn't lock on it yet because of a mutter bug (see below) |
| Brightness down | Consumer brightness down **and** Keyboard F16 (0x07006b) | works (F16 is ignored) | none |
| Brightness up, screenshot, media, volume, Delete | standard codes | work | none |
| Touchpad toggle | handled inside the keyboard | works | none |

**Touchpad:** the report map declares Physical Max = Logical Max (2764 × 1630 in units of 0.01 inch),
so Linux sees a 691 × 407 mm pad and the pointer moves far too fast. The real pad is about 120 × 71 mm,
which is 23 units/mm on both axes. That matches the device tree's `touchpad-xy-resolution = <23 23>`
for `caihong`, and the 8,640 mm² touchpad area given in [reviews][gsmarena].

**Lock key and GNOME:** GNOME's lock shortcut is the text `XF86ScreenSaver`. Mutter turns shortcut
text into a keysym case-insensitively (`xkb_keysym_from_name(…, XKB_KEYSYM_CASE_INSENSITIVE)` in
[`src/core/meta-accel-parse.c`][accel]). Newer libxkbcommon (checked: 1.13.1, xkb-data 2.48) has two keysyms
whose names differ only in case:

| Keysym | Value | Key it's on |
|---|---|---|
| `XF86ScreenSaver` | 0x1008ff2d | `KEY_SCREENLOCK` (Linux 152, xkb 160) |
| `XF86Screensaver` | 0x10081245 | `KEY_SCREENSAVER` (Linux 581, xkb 589) |

A case-insensitive lookup of `XF86ScreenSaver` returns **0x10081245**, the newer one. So GNOME's lock
shortcut ends up on `KEY_SCREENSAVER` only, and a key sending `KEY_SCREENLOCK`, the code systemd's existing
lock-key entries use, never locks. Checked on Ubuntu 26.10 / GNOME 51 in Looking Glass:
`global.display.get_keybinding_action(160, 0)` is 0 and `(589, 0)` is the lock shortcut's ID, and a test grab
of `<Shift>XF86ScreenSaver` also lands on 589 only. Mapped to `screensaver`, the Lock key locks (GNOME Shell
reports `AcceleratorActivated` and calls `org.gnome.ScreenSaver.Lock`). This matches the open report
[mutter #3990][m3990] (GNOME 46 and later). A fix would be to look the name up exactly first and fall back to
the case-insensitive lookup only if that finds nothing.

In plain terms, the key and the shortcut are translated separately, and only the shortcut goes wrong:

1. **The key:** the keyboard sends HID usage 0x070073; the hwdb turns it into `KEY_SCREENLOCK`; GNOME's keymap
   names that key `XF86ScreenSaver` (capital S), and applications receive exactly that.
2. **The shortcut:** GNOME stores its lock shortcut as the text "XF86ScreenSaver"; mutter's case-insensitive
   lookup turns that text into `XF86Screensaver` (small s), the name of the other key, `KEY_SCREENSAVER`.
3. The key arrives as `XF86ScreenSaver` while the shortcut waits for `XF86Screensaver`, so nothing locks.
   Nothing is dropped; the two simply don't match.

This affects more than this keyboard: systemd's `60-keyboard.hwdb` (checked in October 2026) has 14 lines that
map a lock key to `screenlock`, and none of those keys lock the screen in GNOME.

This repo's Linux file still maps Lock to `screenlock`, the same as systemd's hwdb does for other lock keys:
the bug is mutter's to fix, and mapping the key to `screensaver` would only work around it. Until mutter is
fixed, the Lock key doesn't lock the screen in GNOME; other desktops that handle `KEY_SCREENLOCK` aren't
affected.

Testing key codes by changing a running device's keymap (`EVIOCSKEYCODE`) doesn't work under GNOME: libinput
drops codes the device didn't list when it appeared. Change the hwdb and reconnect instead.

**Pairing with a PC** makes the keyboard ignore the tablet while the PC's Bluetooth is on, even if the
keyboard is blocked there; the tablet's pairing is kept. See the README.

[drv]: https://github.com/yaap/kernel_oneplus_sm8650-modules/blob/seventeen/oplus/kernel/device_info/pogo_keyboard/pogo_keyboard_core.c
[caihong]: https://github.com/LineageOS/android_kernel_oneplus_sm8650-devicetrees/blob/lineage-24.0/oplus/oplus_pogo_kb/caihong-oplus-pogopin-kb-23926.dtsi
[erhai]: https://github.com/LineageOS/android_kernel_oneplus_sm8750-devicetrees/blob/lineage-24.0/oplus/oplus_pogo_kb/erhai-oplus-pogopin-kb-eu.dtsi
[iceland]: https://github.com/LineageOS/android_kernel_oneplus_sm8850-devicetrees/blob/lineage-24.0/oplus/oplus_pogo_kb/iceland-oplus-pogopin-kb.dtsi
[mt6991]: https://github.com/realme-kernel-opensource/realme_gt7-AndroidB-vendor-source/blob/master/kernel/kernel_device_modules-6.6/arch/arm64/boot/dts/mediatek/oplus6991_pogopin_kb.dtsi
[mt6897]: https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_mt6897/blob/oneplus/mt6897_v_15.0.2_nord_ce5/kernel/kernel_device_modules-6.1/arch/arm64/boot/dts/mediatek/oplus6897_pogopin_kb.dtsi
[oppo-op]: https://www.oppo.com/cn/oneplus/tablets/
[oppo-tab]: https://www.oppo.com/cn/tablets/
[opk2402]: https://www.ebay.de/itm/336270909258
[gamersky]: https://www.gamersky.com/tech/202510/2035801.shtml
[pad4]: https://digitalwalker.ph/products/smart-keyboard-for-oneplus-pad-4
[gsmarena]: https://m.gsmarena.com/oneplus_pad_2_in_for_review-news-63742.php
[accel]: https://gitlab.gnome.org/GNOME/mutter/-/blob/main/src/core/meta-accel-parse.c
[m3990]: https://gitlab.gnome.org/GNOME/mutter/-/work_items/3990
