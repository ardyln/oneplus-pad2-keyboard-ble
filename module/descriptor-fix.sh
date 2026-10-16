#!/system/bin/sh
# Repairs the keyboard's HID report map cached in bt_config.conf.
#   check    exit 0 = needs repair, 1 = nothing to do, 4 = truncated but repair would be invalid
#   apply    repair (only safe while the Bluetooth stack is not running)
#   restore  put back the original 512-byte map (used by uninstall)

MODDIR=${0%/*}
LOG_TAG=descfix
. "$MODDIR/common.sh"

[ -n "$BB" ] || { log "no busybox found"; exit 3; }
[ -f "$BT_CONFIG" ] || exit 1

# Prints the rewritten config on stdout. Exit status of awk: 0 = changed, 1 = unchanged,
# 4 = truncated map found but repaired map failed validation.
transform() {
    "$BB" awk -v mode="$1" -v mac="$(echo "$KBD_MAC" | tr 'A-F' 'a-f')" \
        -v vid="$KBD_VID" -v pid="$KBD_PID" -v tail="$DESC_TAIL" -v oldtails="$DESC_OLD_TAILS" \
        -v trunc="$DESC_TRUNC_BYTES" -v full="$DESC_FULL_BYTES" -v swaps="$DESC_SWAPS" '
    function hx(s) { s = tolower(s); return (index("0123456789abcdef", substr(s,1,1)) - 1) * 16 + index("0123456789abcdef", substr(s,2,1)) - 1 }
    # Walks HID items: must end exactly on an item boundary with all collections closed.
    function valid(h,   n, i, b, sz, depth) {
        if (h !~ /^[0-9a-f]+$/ || length(h) % 2) return 0
        n = length(h) / 2; i = 0; depth = 0
        while (i < n) {
            b = hx(substr(h, i*2 + 1, 2))
            if (b == 254) { if (i + 1 >= n) return 0; i += 3 + hx(substr(h, i*2 + 3, 2)); continue }
            sz = b % 4; if (sz == 3) sz = 4
            if (b - b % 4 == 160) depth++
            if (b - b % 4 == 192) { depth--; if (depth < 0) return 0 }
            i += 1 + sz
        }
        return (i == n && depth == 0)
    }
    # Replaces whole items equal to "from" with "to", only at item boundaries.
    function swap(h, from, to,   n, i, b, sz, out, item) {
        n = length(h) / 2; i = 0; out = ""
        while (i < n) {
            b = hx(substr(h, i*2 + 1, 2))
            if (b == 254) sz = 2 + hx(substr(h, i*2 + 3, 2)); else { sz = b % 4; if (sz == 3) sz = 4 }
            item = substr(h, i*2 + 1, (1 + sz) * 2)
            out = out (item == from ? to : item)
            i += 1 + sz
        }
        return out
    }
    function swap_all(h, dir,   k, nsw, pair, ab) {
        nsw = split(swaps, pair, " ")
        for (k = 1; k <= nsw; k++) {
            split(pair[k], ab, ":")
            h = (dir > 0) ? swap(h, ab[1], ab[2]) : swap(h, ab[2], ab[1])
        }
        return h
    }
    # A map this module wrote: the 512 cached bytes followed by the current or an older tail.
    function ours_tail(d,   t, k, nt, ot) {
        t = substr(d, trunc*2 + 1)
        if (t == tail) return 1
        nt = split(oldtails, ot, " ")
        for (k = 1; k <= nt; k++) if (t == ot[k]) return 1
        return 0
    }
    function flush(   k, d, f) {
        for (k = 1; k <= cnt; k++) {
            if (ours && vok && pok && buf[k] ~ /^HogpDescriptor = /) {
                d = substr(buf[k], 18)
                if (mode == "fix" && (length(d) == trunc * 2 || (length(d) > trunc * 2 && ours_tail(d)))) {
                    f = swap_all(substr(d, 1, trunc * 2) tail, 1)
                    if (f != d) {
                        if (valid(f) && length(f) == full * 2) { buf[k] = "HogpDescriptor = " f; changed = 1 }
                        else bad = 1
                    }
                }
                if (mode == "restore" && length(d) > trunc * 2 && ours_tail(d)) {
                    buf[k] = "HogpDescriptor = " substr(swap_all(d, -1), 1, trunc * 2); changed = 1
                }
            }
            print buf[k]
        }
        cnt = 0; ours = 0; vok = 0; pok = 0
    }
    /^\[/ { flush(); ours = (tolower($0) == "[" mac "]") }
    { buf[++cnt] = $0 }
    $0 == "HogpVendorId = " vid { vok = 1 }
    $0 == "HogpProductId = " pid { pok = 1 }
    END { flush(); exit(bad ? 4 : (changed ? 0 : 1)) }
    ' "$BT_CONFIG"
}

write_config() {  # $1 = mode (fix|restore)
    TMP="$BT_CONFIG.pad2kbd.tmp"
    transform "$1" > "$TMP"; rc=$?
    if [ $rc -ne 0 ]; then rm -f "$TMP"; return $rc; fi
    if [ ! -s "$TMP" ] || [ "$(wc -l < "$TMP")" -ne "$(wc -l < "$BT_CONFIG")" ]; then
        log "refusing to write: temp file empty or line count differs"; rm -f "$TMP"; return 3
    fi
    chown bluetooth:bluetooth "$TMP"; chmod 0660 "$TMP"
    chcon u:object_r:bluetooth_data_file:s0 "$TMP" 2>/dev/null
    mv -f "$TMP" "$BT_CONFIG"
}

backup_once() {
    mkdir -p "$STATE_DIR"; chmod 0700 "$STATE_DIR"
    if [ ! -f "$STATE_DIR/bt_config.conf.orig" ]; then
        cp -p "$BT_CONFIG" "$STATE_DIR/bt_config.conf.orig" && chmod 0600 "$STATE_DIR/bt_config.conf.orig"
        log "backed up bt_config.conf to $STATE_DIR/bt_config.conf.orig"
    fi
}

case "$1" in
    check)
        transform fix > /dev/null; rc=$?
        [ $rc -eq 4 ] && log "truncated map found but repaired map is invalid; not touching it"
        exit $rc
        ;;
    apply)
        transform fix > /dev/null; rc=$?
        [ $rc -eq 0 ] || { [ $rc -eq 4 ] && log "apply skipped: repaired map would be invalid"; exit $rc; }
        backup_once
        write_config fix; rc=$?
        if [ $rc -eq 0 ]; then log "repaired HID report map for $KBD_MAC ($DESC_FULL_BYTES bytes, size swaps: ${DESC_SWAPS:-none})"
        else log "apply failed rc=$rc"; fi
        exit $rc
        ;;
    restore)
        write_config restore; rc=$?
        if [ $rc -eq 0 ]; then log "restored original $DESC_TRUNC_BYTES-byte report map for $KBD_MAC"; fi
        exit $rc
        ;;
    *)
        echo "usage: $0 check|apply|restore" >&2; exit 2 ;;
esac
