#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

log "starting STA on interface $WLAN_IFACE"

require_cmd ifconfig
ensure_wifi_driver

if ! check_wifi_config; then
    exit 1
fi

show_wifi_config_summary
prepare_sta_interface

log "launching wpa_supplicant"
start_wpa_supplicant
sleep 2

log "launching udhcpc"
start_udhcpc

if wait_for_sta_ip "$STA_CONNECT_TIMEOUT"; then
    log "STA connected successfully"
    show_iface_status
    exit 0
fi

log "STA did not obtain IP within ${STA_CONNECT_TIMEOUT}s"
show_iface_status
exit 1
