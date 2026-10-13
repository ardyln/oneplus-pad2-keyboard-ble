#!/usr/bin/env bash
# Read-only watcher: every 2 s, prints any change in the keyboard's HID_HOST policy history,
# HID/HOGP connection state, pogo attach state and BLE input device presence.
# usage: policy_watch.sh MAC_SUFFIX (e.g. 55:25)
SUF=${1:-55:25}
last=""
while true; do
  bt=$(adb shell dumpsys bluetooth_manager 2>/dev/null | tr -d '\r')
  pol=$(printf '%s\n' "$bt" | grep -E "XX:$SUF: HID_HOST policy changed" | tail -n 1 | sed -E 's/^ +//')
  con=$(printf '%s\n' "$bt" | grep -E ":$SUF : Selected transport" | head -n 1 | sed -E 's/^ +//; s/^[^ ]+ : //')
  inp=$(adb shell dumpsys input 2>/dev/null | tr -d '\r' | grep -cE 'Identifier: vendor 8921, product 14441, sources' )
  pogo=$(adb shell dumpsys input 2>/dev/null | grep -q pogo_touchpad && echo attached || echo detached)
  cur="pogo=$pogo | kbd_input_devices(22d9:3869)=$inp | $con | last_policy_event: ${pol:-none}"
  if [ "$cur" != "$last" ]; then printf '%s  %s\n' "$(date +%T)" "$cur"; last=$cur; fi
  sleep 2
done
