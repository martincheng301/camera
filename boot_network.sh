#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

exec "$SCRIPT_DIR/scripts/boot_network.sh" "$@"
