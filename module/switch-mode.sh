#!/system/bin/sh
# switch-mode.sh attached|detached [force]
# attached: stop the latency client, forbid BLE HID and disconnect it (no double input).
# detached: allow BLE HID, connect, and bond (first time) or start the latency client.
# On a ROM that handles the keyboard itself (rom_native), only the latency client is touched.

MODDIR=${0%/*}
LOG_TAG=switch
. "$MODDIR/common.sh"

MODE=$1
case "$MODE" in attached|detached) ;; *) echo "usage: $0 attached|detached [force]" >&2; exit 2 ;; esac

# At reboot the pogo driver loses the keyboard heartbeat and sends a real "detached" uevent;
# ignore it. (No debounce delay: a real detach should switch to BLE immediately.)
if shutting_down; then
    log "ignored $MODE from ${SRC:-?}: system is shutting down"
    exit 0
fi

mkdir -p "$STATE_DIR"
# Both the uevent listener and the poll loop report each transition; run once per change.
LOCK="$STATE_DIR/switch.lock"
i=0
until mkdir "$LOCK" 2>/dev/null; do
    i=$((i + 1)); [ $i -ge 20 ] && { log "lock busy, skipping $MODE"; exit 0; }
    sleep 1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if [ "$2" != "force" ] && [ "$(cat "$STATE_DIR/mode" 2>/dev/null)" = "$MODE" ]; then
    exit 0
fi
echo "$MODE" > "$STATE_DIR/mode"

# Right after attaching, the pogo driver needs a moment before its frames (with the keyboard's
# address) show up in the kernel log; a new keyboard is picked up here.
if [ "$MODE" = attached ] && [ "$KBD_MAC_SOURCE" != config ] && [ "$KBD_MAC_SOURCE" != override ]; then
    i=0
    until [ -n "$(mac_from_pogo)" ] || [ $i -ge 10 ]; do sleep 0.5; i=$((i + 1)); done
    resolve_kbd_mac
fi
if [ -z "$KBD_MAC" ]; then
    log "keyboard address unknown: attach the keyboard once, or write it to $MAC_OVERRIDE_FILE"
    exit 0
fi

# The ROM's own app pairs and switches HID; only the latency client is started and stopped here.
if rom_native; then
    case "$MODE" in
        attached)
            log "pogo attached (${SRC:-?}) -> stop latency client (ROM handles HID)"
            am stopservice --user 0 -n "$APP_PKG/.LatencyService" >/dev/null 2>&1
            ;;
        detached)
            log "pogo detached (${SRC:-?}) -> start latency client for $KBD_MAC (ROM handles HID)"
            am broadcast --user 0 -a "$APP_PKG.PAIR" -n "$APP_PKG/.PairReceiver" \
                --es mac "$KBD_MAC" --ez pair false >/dev/null 2>&1
            ;;
    esac
    exit 0
fi

case "$MODE" in
    attached)
        log "pogo attached (${SRC:-?}) -> suspend BLE HID for $KBD_MAC"
        am stopservice --user 0 -n "$APP_PKG/.LatencyService" >/dev/null 2>&1
        hidctl suspend "$KBD_MAC"
        ;;
    detached)
        log "pogo detached (${SRC:-?}) -> resume BLE HID for $KBD_MAC"
        hidctl resume "$KBD_MAC"
        am broadcast --user 0 -a "$APP_PKG.PAIR" -n "$APP_PKG/.PairReceiver" \
            --es mac "$KBD_MAC" >/dev/null 2>&1
        ;;
esac
