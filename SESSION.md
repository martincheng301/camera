# Session Notes

## Current Objective

Implement automatic file transfer from board to phone via HTTP + JSON listing CGI, so the phone can discover and pull recordings without manual steps.

## Current Status

All stages 0-7 are implemented and verified:

| Stage | Description | Status |
|-------|-------------|--------|
| 0 | Wi-Fi driver load | Done |
| 1 | AP bring-up (`boot_ap.sh`, `start_ap.sh`, hostapd + DHCP) | Done |
| 2 | AP stability (hostapd IP re-apply, process cleanup) | Done |
| 3 | Minimal provisioning (Wi-Fi credential form + CGI save) | Done |
| 4 | STA networking (`start_sta.sh`, `stop_sta.sh`, wpa_supplicant + udhcpc) | Done |
| 5 | Boot-time state machine (`boot_network.sh`, `S99boot_net`, `S98eth0_static`) | Done |
| 6 | Storage path migration (`/userdata/video0` → `/mnt/sdcard/record`) | Done |
| 7 | Control + video transport (native HTTP endpoints + RTSP) | Done |

## Confirmed Board Facts

- system: BusyBox, init.d convention
- web server: nginx + fcgiwrap (NOT BusyBox httpd)
- nginx config: `/oem/usr/etc/nginx/nginx.conf`
- native web root: `/oem/usr/www/`
- native CGI dir: `/oem/usr/www/cgi-bin/`
- Wi-Fi chip: AIC8800 (BL-M8800DS2, SDIO)
- interface: `wlan0`
- AP IP: `192.168.4.1`, SSID: `CameraBoard_Setup`, passphrase: `12345678`
- eth0 static IP: `192.168.1.200`
- project root on board: `/userdata/ap_test`

## Verified Board-Native Interfaces

Two-layer API:

1. Parameter config:
   - `PUT /cgi-bin/entry.cgi/video/0` with JSON body `{"sResolution":"2880*1616","sOutputDataType":"H.265","iMaxRate":8192,...}`
2. Record control:
   - `PUT /cgi-bin/entry.cgi/event/start-record?duration=60&stream=0`
   - `PUT /cgi-bin/entry.cgi/event/stop-record`
   - Response: `{}`

Both interfaces verified identical over Ethernet (192.168.1.200) and Wi-Fi (STA DHCP IP).

## WiFi Provisioning Flow

AP mode (`boot_ap.sh`):
1. Board creates AP `CameraBoard_Setup`
2. Phone connects, opens `http://192.168.4.1/provision.html`
3. User enters router SSID + PSK
4. Form POSTs to `/cgi-bin/save_wifi.cgi` (nginx -> fcgiwrap -> our `save_wifi.sh`)
5. `save_wifi.sh` writes `wpa_supplicant.conf`, schedules STA switch via `schedule_sta_after_provision`
6. Board switches to STA, joins user router

Key design choice: our provisioning page (`/oem/usr/www/index.html` overwritten by `provision.html`) is served by the native nginx on port 80, NOT by BusyBox httpd. CGI scripts in `/oem/usr/www/cgi-bin/` exec to `/userdata/ap_test/scripts/save_wifi.sh`.

## UDP Device Discovery

On STA connect, `broadcast_sta_ip()` in `lib.sh` sends `CameraBoard:IP`
via `nc -u` to UDP 255.255.255.255:7000. App listens on that port.

## WiFi-Side Test Flow
1. Open `http://<sta-ip>/control.html` (deployed to `/oem/usr/www/control.html`)
2. Set video params via Start Path = `/cgi-bin/entry.cgi/video/0`, paste JSON body
3. Click Start Record -> start recording via `/cgi-bin/entry.cgi/event/start-record`
4. F12 Network tab: compare Request URL, Method, Status, Response with Ethernet side
5. Verify: `ls -l /mnt/sdcard/record` on board
6. Browse/download recordings: `http://<sta-ip>/cgi-bin/videos`

## Video File Browsing

- nginx serves `/userdata/video0` on port 8080 (bind-mounted to SD card at boot if present; raw file download, no directory listing)
- CGI script `/oem/usr/www/cgi-bin/videos` generates HTML file listing at `http://<ip>/cgi-bin/videos`
- Listing page auto-refreshes every 10s, clickable links download via port 8080
- Play in VLC: drag downloaded file into window, Ctrl+J for codec info

## CGI Content-Type Rule (COLLAB_RULES.md)

All CGI shell scripts must output `Content-Type` header BEFORE `set -eu` and BEFORE sourcing dependencies. If any operation before the header fails, `set -e` exits with no HTTP response -> nginx returns 502 with no visible error. See COLLAB_RULES.md `## CGI Shell Script Rules` or `## First Principle: Explain the Why`.

## Important Runtime Paths

- AP deploy root: `/userdata/ap_test`
- runtime dir: `/userdata/ap_test/runtime`
- provisioning output: `/userdata/wifi/wpa_supplicant.conf`, `/userdata/wifi/ap_provision.conf`
- recording output: `/mnt/sdcard/record`
- recording fallback: `/userdata/video0` (auto-fallback via `lib.sh` `detect_storage()`)
- storage boot: `scripts/boot_storage.sh` bind-mounts SD card to `/userdata/video0` if present
- storage status: `status.cgi` returns `storage_dev=sdcard|internal`
- nginx config: `/oem/usr/etc/nginx/nginx.conf`
- web pages (deployed to nginx): `/oem/usr/www/provision.html`, `/oem/usr/www/control.html`
- CGI (deployed to nginx): `/oem/usr/www/cgi-bin/save_wifi.cgi`, `/oem/usr/www/cgi-bin/videos`

## Current Risks

- SD card hot-removal while bind-mounted: I/O errors for new writes, CGI lists return gracefully empty
- target board may not provide `/usr/share/udhcpc/default.script`
- `wpa_supplicant.conf` may be syntactically valid but rejected at runtime
- STA success currently depends on IP acquisition only, does not yet prove full reachability
- nginx `autoindex` module not compiled in (confirmed) -> file browsing requires CGI script

## Web Page Inventory

| Page | Purpose | Deploy to | Access |
|------|---------|-----------|--------|
| `www/provision.html` | Wi-Fi credential form | `/oem/usr/www/` (overwrote native index.html) | `http://192.168.4.1/` |
| `www/control.html` | Record-control test page | `/oem/usr/www/control.html` | `http://<ip>/control.html` |
| `www/cgi-bin/videos` | Video file listing CGI | `/oem/usr/www/cgi-bin/videos` | `http://<ip>/cgi-bin/videos` |

## Handoff

When resuming work in a new session:

1. read `SESSION.md` for current state
2. read `TECHNICAL_ROUTE.md` for roadmap
3. check board: is nginx alive on 80+8080? is filesystem intact?
4. confirm Wi-Fi both AP and STA modes work

