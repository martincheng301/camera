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

if "$SCRIPT_DIR/save_wifi_args.sh" "$ssid" "$psk"; then
    printf 'OK: saved Wi-Fi config for SSID=%s\n' "$ssid"
    exit 0
fi

printf 'ERROR: failed to save Wi-Fi config\n'
