#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

log "setting up recording storage"
setup_sdcard_storage

log "bringing up wifi driver"
ensure_wifi_driver

if check_wifi_config; then
    log "saved Wi-Fi config found, trying STA first"
    if "$SCRIPT_DIR/start_sta.sh" "$@"; then
        log "STA startup succeeded"
        exit 0
    fi
    log "STA startup failed, falling back to AP provisioning"
    rm -f "$WPA_SUPPLICANT_CONF" "$PROVISION_STAGING_FILE"
else
    log "no saved Wi-Fi config, starting AP provisioning"
fi

exec "$SCRIPT_DIR/start_ap.sh" "$@"
