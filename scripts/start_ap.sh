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

kill_process_if_running httpd; sleep 1; start_httpd

log "interface status after AP setup"
show_iface_status
log "AP ready: ssid=$AP_SSID ip=$AP_IP dhcp=$DHCP_BACKEND"

# Disable OSD overlays via rkipc API
disable_osd() {
    local path="$1"
    if command -v wget >/dev/null 2>&1; then
        wget -q -O /dev/null --method=PUT --body-data='{"enabled":0}' \
            "http://127.0.0.1$path" 2>/dev/null
    elif command -v nc >/dev/null 2>&1; then
        printf 'PUT %s HTTP/1.0\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n{"enabled":0}' \
            "$path" | nc -w1 127.0.0.1 80 2>/dev/null
    fi
}
disable_osd /cgi-bin/entry.cgi/osd/0 || true
disable_osd /cgi-bin/entry.cgi/osd/1 || true
