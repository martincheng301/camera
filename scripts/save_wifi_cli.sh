#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

ssid="${1:-}"
psk="${2:-}"

if [ -z "$ssid" ]; then
    echo "usage: sh $0 <ssid> [password]" >&2
    exit 1
fi

if [ -n "$psk" ] && [ "${#psk}" -lt 8 ]; then
    echo "password must be at least 8 characters" >&2
    exit 1
fi

"$SCRIPT_DIR/save_wifi_args.sh" "$ssid" "$psk"

echo "saved Wi-Fi config:"
echo "  SSID=$ssid"
echo "  WPA file=$WPA_SUPPLICANT_CONF"
