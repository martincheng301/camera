#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

mode=$(get_network_mode)
ip_addr=$(get_iface_ipv4)
recording=$(get_recording_status)

printf 'mode=%s\n' "$mode"
printf 'ip=%s\n' "${ip_addr:-}"
printf 'recording=%s\n' "$recording"
