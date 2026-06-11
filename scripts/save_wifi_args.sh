#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

ssid="${1:-}"
psk="${2:-}"

if [ -z "$ssid" ]; then
    echo "missing ssid" >&2
    exit 1
fi

if [ -n "$psk" ] && [ "${#psk}" -lt 8 ]; then
    echo "psk must be at least 8 characters" >&2
    exit 1
fi

ensure_provision_dir

cat >"$PROVISION_STAGING_FILE" <<EOF
SSID=$ssid
PSK=$psk
EOF

cat >"$WPA_SUPPLICANT_CONF" <<EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
network={
    ssid="$ssid"
EOF

if [ -n "$psk" ]; then
    cat >>"$WPA_SUPPLICANT_CONF" <<EOF
    psk="$psk"
EOF
else
    cat >>"$WPA_SUPPLICANT_CONF" <<EOF
    key_mgmt=NONE
EOF
fi

cat >>"$WPA_SUPPLICANT_CONF" <<EOF
}
EOF
