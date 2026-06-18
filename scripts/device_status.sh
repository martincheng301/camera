#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

mode=$(get_network_mode)
ip_addr=$(get_iface_ipv4)
recording=$(get_recording_status)
detect_storage

printf 'mode=%s\n' "$mode"
printf 'ip=%s\n' "${ip_addr:-}"
printf 'recording=%s\n' "$recording"
printf 'storage=%s\n' "$RECORD_DIR"
if grep -qs ' /mnt/sdcard ' /proc/mounts; then
    printf 'storage_dev=sdcard\n'
else
    printf 'storage_dev=internal\n'
fi
