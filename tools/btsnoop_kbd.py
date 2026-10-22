#!/usr/bin/env python3
"""Reads an Android btsnoop_hci.log and reports what happened on one LE peer's links.

    btsnoop_kbd.py LOG PEER timeline          connection-parameter events per connection
    btsnoop_kbd.py LOG PEER delivery [HANDLE] how touchpad reports arrive (default ATT handle 0x0032)
    btsnoop_kbd.py LOG PEER read HANDLE       ATT reads of one attribute (e.g. 0x001e report map,
                                              0x0007 preferred connection parameters)

PEER is the start of the peer's address (e.g. its first three bytes, AA:BB:CC), so the full
address doesn't have to go into a report. Times are the computer's local time.
Get the log with snoop logging set to "full" (Developer options), from
/data/misc/bluetooth/logs/btsnoop_hci.log (and .log.last, which the stack rotates to).
Used for docs/ROM-NATIVE.md; only reads the file, so run it with python3 -I.
"""
import statistics
import struct
import sys
import time

EPOCH = 0x00E03AB44A676000  # btsnoop timestamps are microseconds since year 0


def stamp(ts):
    us = ts - EPOCH
    return time.strftime('%H:%M:%S', time.localtime(us / 1e6)) + '.%03d' % ((us // 1000) % 1000)


def records(path):
    data = open(path, 'rb').read()
    if data[:8] != b'btsnoop\0':
        sys.exit(f'{path}: not a btsnoop file')
    off = 16
    while off + 24 <= len(data):
        _, incl, flags, _, ts = struct.unpack('>IIIIq', data[off:off + 24])
        off += 24
        yield ts, flags, data[off:off + incl]
        off += incl


def walk(path):
    """Yields (ts, kind, handle, info) for HCI events/commands and reassembled ATT/L2CAP PDUs."""
    partial = {}
    for ts, flags, p in records(path):
        if len(p) < 4:
            continue
        if p[0] == 4 and p[1] == 0x3e:                      # LE meta event
            yield ts, 'le', None, (p[3], p[4:])
        elif p[0] == 4 and p[1] == 0x05:                    # disconnection complete
            _, h, reason = struct.unpack('<BHB', p[3:7])
            yield ts, 'disc', h, reason
        elif p[0] == 1:                                     # HCI command
            yield ts, 'cmd', None, (struct.unpack('<H', p[1:3])[0], p[4:])
        elif p[0] == 2:                                     # ACL data
            h, length = struct.unpack('<HH', p[1:5])
            conn, pb, rx = h & 0xfff, (h >> 12) & 3, flags & 1
            frag = p[5:5 + length]
            key = (conn, rx)
            if pb in (0, 2):
                if len(frag) < 4:
                    continue
                l2len, cid = struct.unpack('<HH', frag[:4])
                partial[key] = [l2len, cid, frag[4:]]
            elif key in partial:
                partial[key][2] += frag
            else:
                continue
            l2len, cid, buf = partial[key]
            if len(buf) >= l2len:
                del partial[key]
                yield ts, 'l2cap', conn, (rx, cid, buf[:l2len])


def peers(path):
    out = {}
    for ts, kind, _, info in walk(path):
        if kind == 'le' and info[0] in (0x01, 0x0a, 0x29) and info[1][0] == 0:
            e = info[1]
            out.setdefault(struct.unpack('<H', e[1:3])[0], []).append(
                ':'.join('%02X' % b for b in e[5:11][::-1]))
    return out


def timeline(path, prefix):
    peer = {}
    for ts, kind, h, info in walk(path):
        line = None
        if kind == 'le':
            sub, e = info
            if sub in (0x01, 0x0a, 0x29) and e[0] == 0:
                h = struct.unpack('<H', e[1:3])[0]
                peer[h] = ':'.join('%02X' % b for b in e[5:11][::-1])
                o = 11 if sub == 0x01 else 23
                iv, lat = struct.unpack('<HH', e[o:o + 4])
                line = f'connected at {iv * 1.25} ms, latency {lat}'
            elif sub == 0x03:
                status, h, iv, lat, _ = struct.unpack('<BHHHH', e[:9])
                line = f'interval now {iv * 1.25} ms, latency {lat} (status {status})'
            elif sub == 0x06:
                h, mn, mx, lat, _ = struct.unpack('<HHHHH', e[:10])
                line = f'KEYBOARD asks {mn * 1.25}-{mx * 1.25} ms, latency {lat}'
        elif kind == 'cmd' and info[0] in (0x2013, 0x2020, 0x2021):
            op, prm = info
            h = struct.unpack('<H', prm[:2])[0]
            if op == 0x2021:
                line = f'tablet rejects the keyboard request (reason 0x{prm[2]:02x})'
            else:
                mn, mx, lat = struct.unpack('<HHH', prm[2:8])
                who = 'TABLET asks' if op == 0x2013 else 'tablet accepts'
                line = f'{who} {mn * 1.25}-{mx * 1.25} ms, latency {lat}'
        elif kind == 'disc':
            line = f'disconnected (reason 0x{info:02x})'
        if line and peer.get(h, '').startswith(prefix):
            print(stamp(ts), f'conn {h}:', line)


def delivery(path, prefix, handle):
    peer, notes = {}, {}
    for ts, kind, h, info in walk(path):
        if kind == 'le' and info[0] in (0x01, 0x0a, 0x29) and info[1][0] == 0:
            peer[struct.unpack('<H', info[1][1:3])[0]] = ':'.join('%02X' % b for b in info[1][5:11][::-1])
        elif kind == 'l2cap':
            rx, cid, buf = info
            if rx and cid == 4 and buf[0] == 0x1b and struct.unpack('<H', buf[1:3])[0] == handle \
                    and peer.get(h, '').startswith(prefix):
                notes.setdefault(h, []).append(ts)
    for h, t in notes.items():
        if len(t) < 20:
            continue
        bursts = [[t[0]]]
        for a, b in zip(t, t[1:]):
            (bursts[-1].append(b) if b - a < 4000 else bursts.append([b]))   # < 4 ms apart = one event
        gaps = [(b[0] - a[0]) / 1000 for a, b in zip(bursts, bursts[1:]) if b[0] - a[0] < 200000]
        sizes = [len(b) for b in bursts]
        per_s = {}
        for x in t:
            per_s[x // 1000000] = per_s.get(x // 1000000, 0) + 1
        busy = [v for v in per_s.values() if v >= 20]
        print(f'conn {h} ({stamp(t[0])} - {stamp(t[-1])}): {len(t)} reports, delivered every '
              f'{statistics.median(gaps):.1f} ms (median), {statistics.mean(sizes):.1f} per delivery '
              f'(max {max(sizes)}); while moving {statistics.median(busy) if busy else 0:.0f} reports/s '
              f'(max {max(busy) if busy else 0})')


def read(path, prefix, handle):
    peer, pending = {}, {}
    for ts, kind, h, info in walk(path):
        if kind == 'le' and info[0] in (0x01, 0x0a, 0x29) and info[1][0] == 0:
            peer[struct.unpack('<H', info[1][1:3])[0]] = ':'.join('%02X' % b for b in info[1][5:11][::-1])
        if kind != 'l2cap' or not peer.get(h, '').startswith(prefix):
            continue
        rx, cid, buf = info
        if cid != 4 or not buf:
            continue
        op = buf[0]
        if not rx and op in (0x0a, 0x0c):
            ah = struct.unpack('<H', buf[1:3])[0]
            pending[h] = ah
            if ah == handle:
                off = struct.unpack('<H', buf[3:5])[0] if op == 0x0c else 0
                print(stamp(ts), f'conn {h}: tablet reads 0x{ah:04x} at offset {off}')
        elif rx and op in (0x0b, 0x0d, 0x01) and pending.get(h) == handle:
            pending[h] = None
            if op == 0x01:
                print(stamp(ts), f'conn {h}: error {buf[1:].hex()}')
            else:
                v = buf[1:]
                print(stamp(ts), f'conn {h}: {len(v)} bytes: {v[:8].hex()}..{v[-8:].hex()}'
                      if len(v) > 16 else f'conn {h}: {len(v)} bytes: {v.hex()}')


def main():
    if len(sys.argv) < 4 or sys.argv[3] not in ('timeline', 'delivery', 'read'):
        sys.exit(__doc__)
    path, prefix, cmd = sys.argv[1], sys.argv[2].upper(), sys.argv[3]
    if cmd == 'timeline':
        timeline(path, prefix)
    elif cmd == 'delivery':
        delivery(path, prefix, int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x0032)
    else:
        if len(sys.argv) < 5:
            sys.exit('read needs an ATT handle, e.g. 0x0007')
        read(path, prefix, int(sys.argv[4], 16))


if __name__ == '__main__':
    main()
