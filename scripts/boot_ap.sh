#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

log "bringing up wifi driver"
ensure_wifi_driver

log "starting AP service"
exec "$SCRIPT_DIR/start_ap.sh" "$@"
