#!/bin/sh

BACKEND_DIR=${BACKEND_DIR:-/userdata/ap_test/scripts}

printf 'Content-Type: text/plain\r\n\r\n'
exec "$BACKEND_DIR/device_status.sh"
