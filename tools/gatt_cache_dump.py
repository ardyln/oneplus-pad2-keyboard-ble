#!/usr/bin/env python3
"""Lists services/characteristics/descriptors from an Android Bluetooth gatt_cache_<addr> file.
Layout (observed): u16 version, u16 count, then `count` 38-byte entries:
  u16 handle | 16-byte attribute-type UUID (big-endian) | 16-byte value UUID | u16 a | u16 b
For 0x2800/0x2801 (service): value = service UUID, a = end handle.
For 0x2803 (characteristic): u8 properties, u8 pad, u16 value handle, 16-byte characteristic UUID.
usage: gatt_cache_dump.py FILE"""
import struct
import sys
import uuid

PROPS = ["bcast", "read", "write-no-rsp", "write", "notify", "indicate", "signed-write", "ext"]
KNOWN = {
    "1800": "Generic Access", "1801": "Generic Attribute", "180a": "Device Information",
    "180f": "Battery", "1812": "HID", "2a4d": "HID Report", "2a4b": "Report Map",
    "2a4a": "HID Information", "2a4c": "HID Control Point", "2a4e": "Protocol Mode",
    "2a19": "Battery Level", "2902": "CCC", "2908": "Report Reference", "2a05": "Service Changed",
    "2a29": "Manufacturer", "2a24": "Model", "2a25": "Serial Number", "2a26": "Firmware Rev",
    "2a27": "Hardware Rev", "2a28": "Software Rev", "2a50": "PnP ID", "2a00": "Device Name",
    "2a01": "Appearance", "2a04": "Conn Params", "2aa6": "Central Addr Resolution",
    "2ac9": "Resolvable Private Addr Only", "2a22": "Boot Kbd Input",
}


def name(u):
    s = str(u)
    if s.endswith("-0000-1000-8000-00805f9b34fb") and s.startswith("0000"):
        short = s[4:8]
        return f"0x{short} {KNOWN.get(short, '')}".rstrip()
    return s


data = open(sys.argv[1], "rb").read()
ver, count = struct.unpack_from("<HH", data, 0)
print(f"version={ver} entries={count}")
for i in range(count):
    off = 4 + i * 38
    handle = struct.unpack_from("<H", data, off)[0]
    typ = uuid.UUID(bytes=data[off + 2:off + 18])
    val = uuid.UUID(bytes=data[off + 18:off + 34])
    a, b = struct.unpack_from("<HH", data, off + 34)
    t = name(typ)
    if t.startswith("0x2800") or t.startswith("0x2801"):
        print(f"\nSERVICE {name(val)}  handles 0x{handle:04x}-0x{a:04x}")
    elif t.startswith("0x2803"):
        pbits = data[off + 18]
        vh = struct.unpack_from("<H", data, off + 20)[0]
        cu = uuid.UUID(bytes=data[off + 22:off + 38])
        props = ",".join(p for k, p in enumerate(PROPS) if pbits >> k & 1)
        print(f"  CHAR {name(cu)}  value_handle=0x{vh:04x}  [{props}]")
    else:
        print(f"    desc 0x{handle:04x} {t}")
