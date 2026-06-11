#!/bin/sh

BACKEND_DIR=${BACKEND_DIR:-/userdata/ap_test/scripts}
raw_data="${QUERY_STRING:-}"

get_query_value() {
    key="$1"
    printf '%s' "$raw_data" | tr '&' '\n' | sed -n "s/^$key=//p" | head -n 1
}

action=$(get_query_value action || true)

printf 'Content-Type: text/plain\r\n\r\n'

case "${action:-}" in
    start|stop|status)
        exec "$BACKEND_DIR/control_record.sh" "$action"
        ;;
    *)
        printf 'ERROR: action must be start, stop, or status\n'
        exit 0
        ;;
esac
