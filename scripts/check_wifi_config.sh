#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

if check_wifi_config; then
    echo "Wi-Fi config is present: $WPA_SUPPLICANT_CONF"
    exit 0
fi

exit 1
