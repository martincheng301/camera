# Project Context

## Purpose

This project is a BusyBox-oriented Wi-Fi setup scaffold for a camera board.

Primary product flow:

1. phone connects to board AP
2. board receives Wi-Fi credentials
3. board later joins router in STA mode
4. phone later controls the board and receives video

## Source of Truth

- technical route: `TECHNICAL_ROUTE.md`
- usage and scaffold summary: `README.md`

## Current Development Priority

The priority order from the technical route is:

1. Wi-Fi driver stability
2. AP startup stability
3. provisioning page + credential storage
4. STA connection
5. boot-time network state machine
6. control protocol
7. live video
8. SD card recording path
9. `eth0` static IP persistence

Current active priority: file transfer (list + download + delete) complete. Next: Stage 6 (SD card) or Stage 8 (app integration).

## Board Environment

- OS style: BusyBox
- Wi-Fi chip: AIC8800
- Wi-Fi module: BL-M8800DS2
- bus: SDIO
- expected tools:
  - `hostapd`
  - `ifconfig`
  - `route`
  - `udhcpd` preferred, `dnsmasq` fallback
  - `nginx` with `fcgiwrap` for CGI handling

## Driver Facts

Expected module paths on board:

- `/oem/usr/ko/cfg80211.ko`
- `/oem/usr/ko/aic8800_bsp.ko`
- `/oem/usr/ko/aic8800_fdrv.ko`

Baseline validation:

```sh
insmod /oem/usr/ko/cfg80211.ko
insmod /oem/usr/ko/aic8800_bsp.ko
insmod /oem/usr/ko/aic8800_fdrv.ko
ifconfig -a
```

Success condition:

- `wlan0` appears

## Repository Layout

- `boot_ap.sh`: top-level boot entry
- `start_ap.sh`: top-level AP start entry
- `scripts/boot_ap.sh`: driver load then AP start
- `scripts/start_ap.sh`: AP bring-up
- `scripts/stop_ap.sh`: AP shutdown
- `scripts/start_config_server.sh`: config HTTP server start
- `scripts/save_wifi.sh`: provisioning save handler
- `scripts/save_wifi_args.sh`: shared provisioning save backend
- `scripts/save_wifi_cli.sh`: CLI credential save helper
- `scripts/check_wifi_config.sh`: saved config validation
- `scripts/start_sta.sh`: STA startup helper
- `scripts/stop_sta.sh`: STA shutdown helper
- `boot_network.sh`: top-level Stage 5 auto network entry
- `scripts/boot_network.sh`: Stage 5 STA-first then AP-fallback logic
- `scripts/device_status.sh`: Stage 7 status backend
- `scripts/control_record.sh`: Stage 7 record control backend
- `scripts/lib.sh`: shared helpers and common logic
- `conf/hostapd/hostapd.conf`: AP config template
- `conf/udhcpd/udhcpd.conf`: DHCP config template
- `conf/dnsmasq/dnsmasq.conf`: DHCP fallback template
- `www/provision.html: Wi-Fi provisioning form
- `www/cgi-bin/save_wifi.cgi`: CGI save entry
- `www/control.html`: Stage 7 control page
- `www/cgi-bin/status.cgi`: CGI status entry
- `www/cgi-bin/record.cgi`: CGI record control entry
- `runtime/`: generated runtime files

## Stage Status

- Stage 0: baseline assumptions defined
- Stage 1: AP bring-up scaffold implemented
- Stage 2: AP stability still requires repeated board validation
- Stage 3: minimal provisioning page and save flow implemented
- Stage 4: STA scripts implemented
- Stage 5: minimal boot state machine implemented
- Stage 7: minimal HTTP control channel implemented
- Stage 7: board-native record control and RTSP substream verified

## Standard Network Defaults

- interface: `wlan0`
- board IP: `192.168.4.1`
- netmask: `255.255.255.0`
- SSID: `CameraBoard_Setup`
- passphrase: `12345678`

## AP Startup Sequence

The intended tested order is:

1. load driver if `wlan0` is missing
2. kill conflicting processes:
   - `wpa_supplicant`
   - `hostapd`
   - `udhcpd`
   - `dnsmasq`
3. reset `wlan0`
4. assign AP address
5. start `hostapd`
6. re-apply AP address if needed
7. start DHCP
8. start HTTP config service

This order matters because the AIC8800 path is sensitive to timing and stale interface state.

## Provisioning Paths

Board deployment root:

```sh
/userdata/ap_test
```

Provisioning output:

```sh
/userdata/wifi/ap_provision.conf
/userdata/wifi/wpa_supplicant.conf
```

## Operational Rules

- Do not move to app integration before minimal browser-based provisioning is stable.
- Treat AP repeatability as a gating requirement.
- Validate restart and reboot cycles, not only first-run success.
- Keep board-side paths writable and BusyBox-compatible.

## Stable Validation Targets

AP is considered stable when:

- `wlan0` appears consistently
- AP becomes visible consistently
- phone can connect consistently
- phone gets DHCP consistently
- no stale process blocks next restart

Provisioning is considered stable when:

- phone can open the page on `192.168.4.1`
- credentials are submitted successfully
- config files are written successfully

STA is considered stable when:

- board joins target Wi-Fi
- board gets valid LAN IP
- connectivity checks pass

Current repository status:

- `scripts/start_sta.sh` starts `wpa_supplicant` and `udhcpc`
- `scripts/stop_sta.sh` stops STA-side processes and clears interface state
- `scripts/check_wifi_config.sh` validates presence of saved config
- `scripts/boot_network.sh` chooses STA first when config exists, else AP fallback
- `scripts/save_wifi_args.sh` owns the canonical Wi-Fi config write path
- `scripts/device_status.sh` reports current mode, IP, and recording state
- `scripts/control_record.sh` implements minimal start/stop/status actions
- `scripts/lib.sh` contains AP-to-STA cleanup and wait-for-IP logic

Verified board-native media/control paths:

- record start: `PUT /cgi-bin/entry.cgi/event/start-record`
- record stop: `PUT /cgi-bin/entry.cgi/event/stop-record`
- HTTP response: `{}`
- RTSP preview: `rtsp://<board-ip>/live/1`
- recording output directory: `/mnt/sdcard/record` (fallback: `/userdata/video0`)

## Known Failure Patterns

- `nl80211: Could not configure driver mode`
- `wlan0` missing after module load
- AP visible but connection fails
- connection hangs because DHCP is not running
- `wlan0` loses IP after `hostapd` starts
- stale AP state blocks STA start

## Resume Workflow

When continuing development:

1. read `SESSION.md` for current task state
2. read `TECHNICAL_ROUTE.md` for roadmap and constraints
3. inspect current script behavior in `scripts/`
4. test Stage 4 on board and record the exact observed failure point
5. if Stage 4 passes reliably, start Stage 5 boot-time state machine work


