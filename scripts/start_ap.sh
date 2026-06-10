#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

log "starting AP on interface $WLAN_IFACE"

require_cmd hostapd
require_cmd ifconfig

ensure_wifi_driver

"$SCRIPT_DIR/stop_ap.sh" >/dev/null 2>&1 || true

write_hostapd_conf
prepare_ap_interface
configure_route

log "launching hostapd"
start_hostapd
sleep 1
stabilize_ap_ip 4 1

start_dhcp_server

log "launching httpd"
if start_httpd; then
    show_http_status
fi

log "interface status after AP setup"
show_iface_status
log "AP ready: ssid=$AP_SSID ip=$AP_IP dhcp=$DHCP_BACKEND"
