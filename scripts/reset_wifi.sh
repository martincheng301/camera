#!/bin/sh

printf 'Content-Type: text/plain\r\n\r\n'

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

log "resetting WiFi config"

# Delete saved credentials
rm -f /userdata/wifi/wpa_supplicant.conf
rm -f /userdata/wifi/ap_provision.conf

log "stopping STA"
"$SCRIPT_DIR/stop_sta.sh" >/dev/null 2>&1 || true

log "starting AP mode"
"$SCRIPT_DIR/start_ap.sh" >/dev/null 2>&1 &

printf 'OK: WiFi config cleared, switching to AP mode\n'
