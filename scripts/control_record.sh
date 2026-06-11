#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

action="${1:-}"

case "$action" in
    start)
        start_recording
        printf 'OK: recording started\n'
        ;;
    stop)
        stop_recording
        printf 'OK: recording stopped\n'
        ;;
    status)
        printf 'OK: recording=%s\n' "$(get_recording_status)"
        ;;
    *)
        printf 'ERROR: usage: %s {start|stop|status}\n' "$0" >&2
        exit 1
        ;;
esac
