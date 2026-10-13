#!/usr/bin/env python3
"""Minimal HID report-descriptor walker: prints items, tracks collections and per-report-ID input sizes.
usage: hid_parse.py HEX [--quiet]"""
import sys

MAIN = {0x8: "Input", 0x9: "Output", 0xB: "Feature", 0xA: "Collection", 0xC: "End Collection"}
GLOBAL = {0x0: "Usage Page", 0x1: "Logical Min", 0x2: "Logical Max", 0x3: "Physical Min", 0x4: "Physical Max",
          0x5: "Unit Exp", 0x6: "Unit", 0x7: "Report Size", 0x8: "Report ID", 0x9: "Report Count",
          0xA: "Push", 0xB: "Pop"}
LOCAL = {0x0: "Usage", 0x1: "Usage Min", 0x2: "Usage Max"}


def walk(data, quiet=False):
    i, depth, size, count, rid = 0, 0, 0, 0, 0
    bits = {}
    stack = []
    while i < len(data):
        b = data[i]
        n = (0, 1, 2, 4)[b & 3]
        typ, tag = (b >> 2) & 3, b >> 4
        if i + 1 + n > len(data):
            return dict(ok=False, end=i, depth=depth, bits=bits, partial=data[i:].hex())
        v = int.from_bytes(data[i + 1:i + 1 + n], "little")
        name = (MAIN, GLOBAL, LOCAL, {}).__getitem__(typ).get(tag, f"?{typ}/{tag:x}")
        if typ == 1:
            if tag == 7: size = v
            elif tag == 9: count = v
            elif tag == 8: rid = v
            elif tag == 0xA: stack.append((size, count, rid))
            elif tag == 0xB and stack: size, count, rid = stack.pop()
        if typ == 0:
            if tag == 0xC: depth -= 1
            if tag in (0x8,): bits[rid] = bits.get(rid, 0) + size * count
        if not quiet:
            print(f"{i:4d}  {'  ' * depth}{data[i:i+1+n].hex():<10} {name} {v:#x}")
        if typ == 0 and tag == 0xA: depth += 1
        i += 1 + n
    return dict(ok=True, end=i, depth=depth, bits=bits, partial="")


if __name__ == "__main__":
    d = bytes.fromhex(sys.argv[1])
    r = walk(d, quiet="--quiet" in sys.argv)
    print(f"len={len(d)} parsed_to={r['end']} complete={r['ok']} open_collections={r['depth']} "
          f"partial_item={r['partial'] or '-'}")
    print("input bytes per report id:", {k: v / 8 for k, v in r["bits"].items()})
