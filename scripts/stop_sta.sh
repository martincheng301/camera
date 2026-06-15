#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

log "stopping udhcpc"
stop_by_pidfile "$UDHCPC_PID_FILE"

log "stopping wpa_supplicant"
stop_by_pidfile "$WPA_SUPPLICANT_PID_FILE"

kill_process_if_running udhcpc
kill_process_if_running wpa_supplicant


clear_iface_addr

log "STA stopped"
