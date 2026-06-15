# Camera Board Technical Route

## Scope

This document is the step-by-step implementation route for the camera board project.

Current target:

- phone connects to board AP
- board supports later Wi-Fi provisioning
- board supports later STA networking
- board supports later control + video streaming

This route is ordered from simple validation to full integration.

## Stage 0: Baseline

### Goal

Confirm the board can expose a usable Wi-Fi interface before touching AP, DHCP, or app integration.

### Actions

1. Identify Wi-Fi chipset and bus.
2. Confirm driver modules exist.
3. Manually load required modules.
4. Confirm `wlan0` appears.

### Current board facts

- system style: BusyBox
- Wi-Fi chip: AIC8800
- module: BL-M8800DS2
- bus: SDIO
- driver modules:
  - `/oem/usr/ko/cfg80211.ko`
  - `/oem/usr/ko/aic8800_bsp.ko`
  - `/oem/usr/ko/aic8800_fdrv.ko`

### Validation

Run:

```sh
insmod /oem/usr/ko/cfg80211.ko
insmod /oem/usr/ko/aic8800_bsp.ko
insmod /oem/usr/ko/aic8800_fdrv.ko
ifconfig -a
```

Success condition:

- `wlan0` exists

### Common issues

- `unknown symbol`
  - usually missing dependency such as `cfg80211.ko`
- no `wlan0`
  - driver not loaded
  - SDIO probe failed
  - firmware missing

## Stage 1: AP Bring-Up

### Goal

Bring up a board AP so the phone can discover and connect to it.

### Current implementation

Files in `/userdata/ap_test`:

- `boot_ap.sh`
- `start_ap.sh`
- `scripts/boot_ap.sh`
- `scripts/start_ap.sh`
- `scripts/stop_ap.sh`
- `scripts/lib.sh`
- `conf/hostapd/hostapd.conf`
- `conf/udhcpd/udhcpd.conf`

### Final tested startup sequence

1. load Wi-Fi driver if `wlan0` is missing
2. kill conflicting processes:
   - `wpa_supplicant`
   - `hostapd`
   - `udhcpd`
   - `dnsmasq`
3. reset `wlan0`
4. assign AP address
5. start `hostapd`
6. re-apply AP address if driver cleared it
7. start `udhcpd`

### Why this order matters

The AIC8800 driver can fail AP startup if:

- `wpa_supplicant` or old `hostapd` is still holding `wlan0`
- `hostapd` starts immediately after driver load
- the driver clears interface IP during AP mode switch

Typical symptom:

```sh
nl80211: Could not configure driver mode
```

This is mainly a timing/state problem, not only a DHCP problem.

### Run

```sh
cd /userdata/ap_test
sh ./boot_ap.sh
```

### Validation

Success conditions:

1. logs show `AP-ENABLED`
2. phone can discover `CameraBoard_Setup`
3. phone can connect
4. phone receives `192.168.4.x`
5. board side `wlan0` holds `192.168.4.1`

### Manual checks

```sh
ifconfig wlan0
ps | grep hostapd
ps | grep udhcpd
cat /userdata/ap_test/runtime/hostapd.conf
cat /userdata/ap_test/runtime/udhcpd.conf
```

### Common issues

#### `Permission denied`

Fix:

```sh
chmod +x /userdata/ap_test/start_ap.sh
chmod +x /userdata/ap_test/boot_ap.sh
chmod +x /userdata/ap_test/scripts/*.sh
```

#### phone sees AP but cannot connect

Check:

- `hostapd` actually started
- conflicting processes were killed
- interface reset completed

#### phone keeps spinning during connect

Usually DHCP not running or AP interface has no IP.

Check:

```sh
ifconfig wlan0
ps | grep udhcpd
```

#### `udhcpd` cannot start due to lease path

Resolved by storing lease file under:

```sh
/userdata/ap_test/runtime/udhcpd.leases
```

#### `wlan0` loses IP after `hostapd` starts

Resolved by re-applying `192.168.4.1` after `hostapd` enters AP state.

## Stage 2: AP Stability

### Goal

Turn the current successful AP test into a repeatable and stable workflow.

### Actions

1. reboot board
2. run `sh ./boot_ap.sh`
3. connect phone
4. disconnect and reconnect
5. stop AP and restart AP
6. repeat multiple times

### Validation

Success means:

- `wlan0` always appears
- AP always becomes visible
- phone always gets an IP
- no stale `hostapd` or `udhcpd` process blocks next run

### Exit criteria

AP test is considered stable only after repeated pass across reboots and restart cycles.

## Stage 3: Minimal Provisioning Service

### Goal

Allow the phone to submit target Wi-Fi credentials while connected to the board AP.

### Recommended approach

Start with a minimal HTTP page instead of app integration.

Board side behavior:

1. AP starts
2. lightweight HTTP service starts on `192.168.4.1`
3. phone opens a page in browser
4. user enters:
   - target SSID
   - target password
5. board stores configuration to persistent storage

### Suggested files

- `/userdata/ap_test/www/provision.html`
- `/userdata/ap_test/scripts/save_wifi.sh`
- `/userdata/ap_test/scripts/start_config_server.sh`

### Suggested storage path

```sh
/userdata/wifi/wpa_supplicant.conf
```

or a board-local staging file first, for example:

```sh
/userdata/wifi/ap_provision.conf
```

### Validation

Success means:

- phone can open provisioning page
- credentials can be submitted
- board writes configuration successfully

## Stage 4: STA Networking

### Goal

After provisioning, the board stops AP mode and joins the target router.

### Flow

1. stop `udhcpd`
2. stop `hostapd`
3. clear AP IP from `wlan0`
4. launch `wpa_supplicant`
5. request address by DHCP client
6. verify board gets LAN IP

### Suggested files

- `/userdata/ap_test/scripts/start_sta.sh`
- `/userdata/ap_test/scripts/stop_sta.sh`
- `/userdata/ap_test/scripts/check_wifi_config.sh`

### Validation

Success means:

- board joins target Wi-Fi
- board obtains valid IP
- board can ping gateway or known host

### Reference test order

1. save credentials:

```sh
sh /userdata/ap_test/scripts/save_wifi_cli.sh TestAP 12345678
```

2. verify config:

```sh
sh /userdata/ap_test/scripts/check_wifi_config.sh
```

3. stop AP and start STA:

```sh
sh /userdata/ap_test/scripts/start_sta.sh
```

4. inspect interface:

```sh
ifconfig wlan0
```

### Common issues

- stale AP state not cleaned before STA startup
- bad `wpa_supplicant.conf`
- wrong interface name
- DHCP client not running

## Stage 5: Boot-Time State Machine

### Goal

Make network behavior automatic at boot.

### Desired logic

1. boot
2. load AIC8800 driver
3. check whether saved Wi-Fi config exists
4. if config exists:
   - attempt STA connect
5. if config missing or STA connect fails:
   - start AP provisioning mode

### Suggested boot entry

BusyBox system usually integrates via:

- `/etc/init.d/`
- `/etc/rcS`
- `/etc/init.d/rcS`
- `/etc/rc.local`

### Validation

Success means:

- first boot without config enters AP mode
- later boot with config enters STA mode
- STA failure can fall back to AP mode

## Stage 6: Storage Path Migration

### Goal

Move recording output to SD card.

### Target path

```sh
/mnt/sdcard
```

### Suggested behavior

1. detect SD card mount
2. verify writable state
3. record to `/mnt/sdcard/record/`
4. if unavailable:
   - fail clearly
   - or fall back to internal path if product policy allows

### Validation

Success means:

- recordings land on SD card
- insufficient space is handled
- absent SD card is handled

## Stage 7: Control + Video Transport

### Goal

Add remote device control and live video transport for the phone.

### Recommended split

- control channel:
  - HTTP
  - TCP
  - WebSocket
- video channel:
  - RTSP first for validation
  - evaluate WebRTC only if lower latency is required later

### Suggested rollout

1. control commands first
   - start record
   - stop record
   - query status
   - query storage
2. live video next
3. integrated app flow last

### Validation

Success means:

- phone can issue commands reliably
- video preview is available
- control and video do not block each other

### Verified board-native interfaces

Current confirmed board behavior:

- start record:

```sh
PUT /cgi-bin/entry.cgi/event/start-record
```

- stop record:

```sh
PUT /cgi-bin/entry.cgi/event/stop-record
```

- typical HTTP response:

```sh
{}
```

- RTSP substream preview:

```sh
rtsp://<board-ip>/live/1
```

- current recording output path:

```sh
/userdata/video0
```

### Current Stage 7 conclusion

For this board, the preferred Stage 7 path is:

- control channel: native HTTP endpoints
- preview channel: RTSP substream `/live/1`
- recording verification: inspect `/userdata/video0`

## Stage 8: App Integration

### Goal

Complete end-to-end user flow:

- phone connects to board AP
- phone submits router credentials
- board joins router
- phone rediscovers board
- phone previews video
- phone controls capture

### Recommended order

1. browser-based provisioning first
2. app-based provisioning second
3. app device discovery
4. app live preview
5. app record control

### Validation

Success means:

- first-use provisioning works
- reconnection logic works after AP to STA transition
- preview and capture both work from phone

## Priority Order

Recommended development priority:

1. Wi-Fi driver stability
2. AP startup stability
3. provisioning page + credential storage
4. STA connection
5. boot-time network state machine
6. control protocol
7. live video
8. SD card recording path
9. `eth0` static IP persistence


## Stage Completion Status

| Stage | Description | Status |
|-------|-------------|--------|
| 0 | Wi-Fi driver load | Done |
| 1 | AP bring-up | Done |
| 2 | AP stability | Done |
| 3 | Minimal provisioning (form + CGI save) | Done |
| 4 | STA networking | Done |
| 5 | Boot-time state machine | Done |
| 6 | Storage path migration (SD card) | Not started |
| 7 | Control + video transport | Done |
| 8 | App integration | Not started |

## Board Web Server

The board runs nginx + fcgiwrap (NOT BusyBox httpd). Config at `/oem/usr/etc/nginx/nginx.conf`. Symlink `/etc/nginx/nginx.conf` -> `/oem/usr/etc/nginx/nginx.conf` eliminates manual `-c` parameter.

## Verified Native Interfaces

1. Parameter config: `PUT /cgi-bin/entry.cgi/video/0` (JSON body with resolution, bitrate, codec, GOP, etc.)
2. Record control: `PUT /cgi-bin/entry.cgi/event/start-record?duration=60&stream=0` / `stop-record` (response `{}`)
3. RTSP preview: `rtsp://<ip>/live/1`
4. Recording output: `/userdata/video0`
5. Video file browse: `http://<ip>/cgi-bin/videos` -> download via port 8080