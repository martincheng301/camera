#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

log "stopping udhcpd"
stop_by_pidfile "$UDHCPD_PID_FILE"

log "stopping dnsmasq"
stop_by_pidfile "$DNSMASQ_PID_FILE"

log "stopping hostapd"
stop_by_pidfile "$HOSTAPD_PID_FILE"

log "stopping httpd"
stop_by_pidfile "$HTTPD_PID_FILE"

kill_process_if_running wpa_supplicant
kill_process_if_running hostapd
kill_process_if_running udhcpd
kill_process_if_running dnsmasq
kill_process_if_running httpd

clear_iface_addr

log "AP stopped"
