# Session Notes

## Current Objective

Capture the verified board-native Stage 7 interfaces in project context and prepare for the next storage-path stage.

## Current Status

- Technical route is defined in `TECHNICAL_ROUTE.md`.
- AP scaffold already exists in this workspace.
- Current implementation covers:
  - Wi-Fi driver loading for AIC8800
  - AP startup scripts
  - DHCP config
  - minimal provisioning web page
  - Wi-Fi credential save scripts
  - STA start/stop helper scripts
- Stage 4 code is now implemented in the repository.
- Stage 5 boot entry now exists as `boot_network.sh`.
- Stage 7 minimal control endpoints now exist for status and record control.
- CGI provisioning now schedules a delayed background STA switch after save.
- Board-native record control and RTSP preview paths are now verified.

## Confirmed Board Assumptions

- system style: BusyBox
- Wi-Fi chip: AIC8800
- module: BL-M8800DS2
- bus: SDIO
- default interface: `wlan0`
- default AP IP: `192.168.4.1`
- default AP SSID: `CameraBoard_Setup`

## Immediate Milestone

Stage 7 board-native control and preview paths are validated.

Definition:

1. record control works through native HTTP endpoints
2. RTSP substream preview works through `/live/1`
3. recordings are written under `/userdata/video0`

## Recommended Next Work

1. update `TECHNICAL_ROUTE.md` with verified Stage 7 interfaces
2. begin Stage 6 storage-path migration from `/userdata/video0` to `/mnt/sdcard/record/`
3. define SD card detection and fallback behavior

## Board-Side Validation Checklist

- `PUT /cgi-bin/entry.cgi/event/start-record` returns `{}`
- `PUT /cgi-bin/entry.cgi/event/stop-record` returns `{}`
- `rtsp://<board-ip>/live/1` previews successfully
- recordings appear under `/userdata/video0`

## Important Runtime Paths

- AP deploy root on board: `/userdata/ap_test`
- runtime directory: `/userdata/ap_test/runtime`
- provisioning output:
  - `/userdata/wifi/ap_provision.conf`
  - `/userdata/wifi/wpa_supplicant.conf`

## Current Risks

- target board may not provide `/usr/share/udhcpc/default.script`
- STA may fail if AP state is not fully cleaned first
- `wpa_supplicant.conf` may be syntactically valid but still rejected by runtime
- STA success currently depends on IP acquisition and does not yet prove full network reachability

## Handoff

When resuming work in a new session:

1. read `TECHNICAL_ROUTE.md`
2. read `PROJECT_CONTEXT.md`
3. inspect current scripts under `scripts/`
4. compare real-board STA results against this file
