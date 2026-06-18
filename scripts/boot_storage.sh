#!/bin/sh
# Bind-mount /mnt/sdcard/record/ onto /userdata/video0 at boot if SD card present.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

setup_sdcard_storage
