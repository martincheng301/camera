#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

raw_data="${QUERY_STRING:-}"

urldecode() {
    value="$1"
    value=$(printf '%s' "$value" | tr '+' ' ')
    value=$(printf '%b' "$(printf '%s' "$value" | sed 's/%/\\x/g')")
    printf '%s' "$value"
}

get_query_value() {
    key="$1"
    printf '%s' "$raw_data" | tr '&' '\n' | sed -n "s/^$key=//p" | head -n 1
}

ssid_encoded=$(get_query_value ssid || true)
psk_encoded=$(get_query_value psk || true)

ssid=$(urldecode "${ssid_encoded:-}")
psk=$(urldecode "${psk_encoded:-}")

printf 'Content-Type: text/plain\r\n\r\n'

if [ -z "$ssid" ]; then
    printf 'ERROR: missing ssid\n'
    exit 0
fi

if [ -n "$psk" ] && [ "${#psk}" -lt 8 ]; then
    printf 'ERROR: psk must be at least 8 characters\n'
    exit 0
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

printf 'OK: saved Wi-Fi config for SSID=%s\n' "$ssid"
