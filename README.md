# Camera Board AP Test

Production-ready Wi-Fi provisioning, recording, and file-transfer system for
Rockchip IP camera boards running BusyBox + nginx.

Handover-ready: all deployment files are in this directory.  A factory board
can be brought to full functionality by following the steps below.

---

## Table of Contents

1. [Hardware & Prerequisites](#1-hardware--prerequisites)
2. [Directory Layout](#2-directory-layout)
3. [From a Factory Board](#3-from-a-factory-board)
4. [Boot Flow](#4-boot-flow)
5. [Usage](#5-usage)
6. [Storage Architecture](#6-storage-architecture)
7. [HTTP API Reference](#7-http-api-reference)
8. [Verification Checklist](#8-verification-checklist)
9. [Troubleshooting](#9-troubleshooting)
10. [File Reference](#10-file-reference)

---

## 1. Hardware & Prerequisites

### Board

| Item | Value |
|------|-------|
| SoC  | Rockchip (RV1109 / RV1126) |
| Wi-Fi| AIC8800 (BL-M8800DS2, SDIO) |
| Flash| Internal flash with `/userdata` partition |
| SD   | Optional — `/dev/mmcblk0p6` auto-mounted to `/mnt/sdcard` |

### Host computer

- ADB or serial (115200 baud) to reach board shell
- Git (optional, for version tracking)

### Board-side tools verified

| Tool | Purpose |
|------|---------|
| `nginx` + `fcgiwrap` | HTTP server + CGI |
| `hostapd` | AP mode |
| `wpa_supplicant` | STA (client) mode |
| `udhcpd` or `dnsmasq` | DHCP server for AP |
| `udhcpc` | DHCP client for STA |
| `ifconfig` / `ip` | Interface management |

---

## 2. Directory Layout

```
board app/
├── boot_network.sh          # Top-level boot entry (auto AP/STA)
├── boot_ap.sh               # One-shot AP entry
├── start_ap.sh              # AP entry (driver + start)
├── nginx.conf               # nginx config (port 80 CGI + 8080 file server)
├── rkipc.ini                # SDK recording config (folder_name=record)
│
├── scripts/
│   ├── lib.sh               # Shared helpers (network, recording, storage)
│   ├── boot_storage.sh      # SD card bind-mount setup
│   ├── boot_network.sh      # Auto network state-machine
│   ├── start_ap.sh          # AP bring-up
│   ├── stop_ap.sh           # AP teardown
│   ├── start_sta.sh         # STA bring-up
│   ├── stop_sta.sh          # STA teardown
│   ├── boot_ap.sh           # Driver + AP one-shot
│   ├── control_record.sh    # Record start/stop/status backend
│   ├── device_status.sh     # Network + recording + storage status
│   ├── save_wifi.sh         # CGI backend for Wi-Fi provisioning
│   ├── save_wifi_args.sh    # Wi-Fi config writer
│   ├── save_wifi_cli.sh     # CLI provisioning helper
│   ├── check_wifi_config.sh # Config existence check
│   └── start_config_server.sh  # Config page server (legacy)
│
├── init.d/
│   ├── S97mount_sdcard      # SD card auto-mount
│   ├── S98eth0_static       # eth0 static IP (192.168.1.200)
│   └── S99boot_net          # Boot-time network state machine
│
├── conf/
│   ├── hostapd/hostapd.conf     # AP template
│   ├── udhcpd/udhcpd.conf       # DHCP template (preferred)
│   └── dnsmasq/dnsmasq.conf     # DHCP fallback template
│
└── www/
    ├── control.html          # Record test page
    ├── provision.html        # Wi-Fi provisioning form
    └── cgi-bin/
        ├── save_wifi.cgi     # Wi-Fi save endpoint
        ├── status.cgi        # Device status endpoint
        ├── record.cgi        # Record control endpoint
        ├── list              # Video file JSON listing
        ├── delete            # Video file deletion
        └── videos            # Video file HTML listing
```

---

## 3. From a Factory Board

### 3.1 — Get shell access

Connect via serial (115200 baud) or ADB:

```sh
adb shell
# or
screen /dev/ttyUSB0 115200
```

### 3.2 — Verify board tools

```sh
which nginx
which fcgiwrap
which hostapd
which wpa_supplicant
which udhcpd
which ifconfig
```

Any missing tool needs to be added to the board firmware build.

### 3.3 — Create project directory

```sh
mkdir -p /userdata/ap_test
```

### 3.4 — Push all files

From host computer:

```sh
# Shell scripts + config templates
adb push scripts    /userdata/ap_test/
adb push conf       /userdata/ap_test/
adb push init.d     /userdata/ap_test/

# Boot wrappers
adb push boot_network.sh /userdata/ap_test/
adb push boot_ap.sh      /userdata/ap_test/
adb push start_ap.sh     /userdata/ap_test/

# nginx config
adb push nginx.conf /oem/usr/etc/nginx/nginx.conf

# rkipc config
adb push rkipc.ini  /oem/usr/etc/rkipc.ini

# Web pages
adb push www/control.html   /oem/usr/www/
adb push www/provision.html /oem/usr/www/

# CGI scripts
adb push www/cgi-bin/save_wifi.cgi  /oem/usr/www/cgi-bin/
adb push www/cgi-bin/status.cgi     /oem/usr/www/cgi-bin/
adb push www/cgi-bin/record.cgi     /oem/usr/www/cgi-bin/
adb push www/cgi-bin/list           /oem/usr/www/cgi-bin/
adb push www/cgi-bin/delete         /oem/usr/www/cgi-bin/
adb push www/cgi-bin/videos         /oem/usr/www/cgi-bin/
```

### 3.5 — Set permissions

```sh
chmod +x /userdata/ap_test/scripts/*.sh
chmod +x /userdata/ap_test/boot_*.sh
chmod +x /userdata/ap_test/start_ap.sh
chmod +x /userdata/ap_test/init.d/*
chmod +x /oem/usr/www/cgi-bin/*
```

### 3.6 — Reload nginx

```sh
nginx -s reload
```

### 3.7 — Register boot scripts

Link the init.d scripts so they run at startup.  The exact directory
depends on the board's init system (try each):

```sh
# rcS.d style (most common)
ln -sf /userdata/ap_test/init.d/S97mount_sdcard /etc/rcS.d/S97mount_sdcard
ln -sf /userdata/ap_test/init.d/S98eth0_static  /etc/rcS.d/S98eth0_static
ln -sf /userdata/ap_test/init.d/S99boot_net     /etc/rcS.d/S99boot_net

# init.d style
ln -sf /userdata/ap_test/init.d/S99boot_net /etc/init.d/S99boot_net
update-rc.d S99boot_net defaults
```

### 3.8 — Configure SD card auto-mount (optional)

If the board does not auto-mount the SD card, add an `/etc/fstab` entry:

```sh
echo '/dev/mmcblk0p6  /mnt/sdcard  auto  defaults  0  0' >> /etc/fstab
```

Verify the block device name:

```sh
ls -l /dev/mmcblk*
```

### 3.9 — Reboot and verify

```sh
reboot
# After reboot:
mount | grep sdcard       # SD card mounted?
ps | grep nginx            # nginx running?
ps | grep hostapd          # AP started (if no Wi-Fi config saved)?
ifconfig wlan0             # Has IP 192.168.4.1?
```

---

## 4. Boot Flow

```
Power on
  │
  ├─ /etc/rcS.d/S97mount_sdcard   — mount SD card if present
  ├─ /etc/rcS.d/S98eth0_static    — set eth0 IP (192.168.1.200)
  └─ /etc/rcS.d/S99boot_net
       │
       └─ /userdata/ap_test/boot_network.sh
            │
            ├─ setup_sdcard_storage()    — bind-mount SD → /userdata/video0
            │                              falls back to internal flash
            │
            └─ check saved Wi-Fi config?
                 ├─ yes → start_sta.sh    — join router
                 │         ├─ success → done (STA mode)
                 │         └─ fail    → start_ap.sh (fallback)
                 └─ no  → start_ap.sh    — AP mode (CameraBoard_Setup)
```

Two boot modes:

| Mode | Trigger | Phone action |
|------|---------|--------------|
| AP   | No saved Wi-Fi config | Connect to `CameraBoard_Setup`, open `http://192.168.4.1` |
| STA  | Saved config exists | Find board on LAN, open `http://<sta-ip>/control.html` |

---

## 5. Usage

### First-time provisioning

1. Board boots in AP mode (SSID `CameraBoard_Setup`, password `12345678`)
2. Phone connects to the AP
3. Phone opens `http://192.168.4.1` (provisioning form)
4. Enter router SSID + password, submit
5. Board saves config, switches to STA mode, joins the router
6. Phone reconnects to the router, discovers board via its new IP

### Recording

```sh
# Start (60 s duration, main stream)
curl -X PUT 'http://<board-ip>/cgi-bin/entry.cgi/event/start-record?duration=60&stream=0'

# Stop
curl -X PUT 'http://<board-ip>/cgi-bin/entry.cgi/event/stop-record'

# Status
curl http://<board-ip>/cgi-bin/status.cgi
# Returns: mode=ap|sta  ip=...  recording=recording|idle  storage=...  storage_dev=sdcard|internal
```

### File transfer

```sh
# List recordings
curl http://<board-ip>/cgi-bin/list
# {"dir":"/mnt/sdcard/record","recording":false,"files":[{"name":"...","size":...,"mtime":...},...]}

# Download via port 8080
curl http://<board-ip>:8080/<filename> -o <filename>

# Delete (free space on board)
curl -X POST 'http://<board-ip>/cgi-bin/delete?name=<filename>'
```

### Browser pages

| URL | Purpose |
|-----|---------|
| `http://<ip>/` | Provisioning form (AP mode) |
| `http://<ip>/control.html` | Record test page |
| `http://<ip>/cgi-bin/videos` | HTML video file list (auto-refresh) |

---

## 6. Storage Architecture

Two-layer design for SD card resilience:

```
Boot:  setup_sdcard_storage()
         │
         ├─ SD card mounted? ──Yes──→ mount --bind /mnt/sdcard/record
         │                                      /userdata/video0
         └─ No ──→ /userdata/video0 stays on internal flash

Runtime:  detect_storage()
            │
            ├─ /proc/mounts has /mnt/sdcard?
            │    └─ Yes ──→ RECORD_DIR=/mnt/sdcard/record
            └─ No ──→ RECORD_DIR=/userdata/video0
```

| Component | Path | Notes |
|-----------|------|-------|
| nginx port 8080 | `/userdata/video0` | Fixed; bind-mounted to SD at boot if present |
| CGI scripts | `$RECORD_DIR` (dynamic) | `/mnt/sdcard/record` or `/userdata/video0` |
| SDK recording | `/mnt/sdcard/record` | Controlled by `rkipc.ini` |

If the SD card is removed after boot, `setup_sdcard_storage()` cleans up
the stale bind mount.  Run it manually after reinserting the card:

```sh
sh /userdata/ap_test/scripts/boot_storage.sh
```

---

## 7. HTTP API Reference

### Port 80 — nginx + fcgiwrap

| Method | Path | Description |
|--------|------|-------------|
| GET | `/cgi-bin/list` | JSON file listing |
| GET | `/cgi-bin/videos` | HTML file listing |
| GET | `/cgi-bin/status.cgi` | Device status |
| GET | `/cgi-bin/record.cgi?action=status` | Recording status |
| POST | `/cgi-bin/delete?name=<file>` | Delete a recording |
| PUT | `/cgi-bin/entry.cgi/event/start-record?duration=60&stream=0` | Start recording (native) |
| PUT | `/cgi-bin/entry.cgi/event/stop-record` | Stop recording (native) |
| PUT | `/cgi-bin/entry.cgi/video/0` | Set video parameters (JSON body) |

### Port 8080 — nginx raw file server

| Method | Path | Description |
|--------|------|-------------|
| GET | `/<filename>` | Download recording file (zero-copy) |

### Preview stream

```
rtsp://<board-ip>/live/1
```

---

## 8. Verification Checklist

### Boot

- [ ] Board boots, nginx responds on port 80
- [ ] No saved config → AP visible (`CameraBoard_Setup`)
- [ ] Saved config → STA connects to router
- [ ] eth0 has IP `192.168.1.200`

### Provisioning

- [ ] Phone connects to AP, gets `192.168.4.x`
- [ ] `http://192.168.4.1` shows provisioning form
- [ ] Submitting credentials writes `/userdata/wifi/wpa_supplicant.conf`
- [ ] Board switches to STA, joins router

### Recording

- [ ] `PUT /cgi-bin/entry.cgi/event/start-record` returns `{}`
- [ ] File appears in `$RECORD_DIR`
- [ ] `/cgi-bin/list` lists the file
- [ ] Port 8080 serves the file for download

### Storage fallback

- [ ] With SD card: `storage_dev=sdcard`, files in `/mnt/sdcard/record`
- [ ] Without SD card: `storage_dev=internal`, files in `/userdata/video0`
- [ ] Removing SD card after boot does not crash CGI scripts

---

## 9. Troubleshooting

### Board boots but no AP visible

```sh
# Check wlan0
ifconfig wlan0
# Expected: 192.168.4.1

# Check hostapd
ps | grep hostapd

# Reload driver manually
cd /userdata/ap_test
sh boot_network.sh
```

### Phone connects but no IP

```sh
ps | grep udhcpd
ps | grep dnsmasq
# Expected: one DHCP server running
```

### nginx returns 502 on CGI

```sh
# Check fcgiwrap
ps | grep fcgiwrap

# Check CGI script permissions
ls -l /oem/usr/www/cgi-bin/

# Check Content-Type header rule: CGI scripts must print
# "Content-Type: ..." BEFORE any other output and BEFORE
# set -eu / sourcing dependencies.
```

### Recording file not appearing

```sh
# Check storage status
curl http://127.0.0.1/cgi-bin/status.cgi

# Check recording directory exists
ls -l /userdata/video0
ls -l /mnt/sdcard/record

# Verify rkipc is configured
cat /oem/usr/etc/rkipc.ini | grep -A2 '\[storage\.0\]'
```

### SD card not detected

```sh
ls -l /dev/mmcblk*
mount | grep sdcard
# If device exists but not mounted:
mkdir -p /mnt/sdcard
mount /dev/mmcblk0p6 /mnt/sdcard
```

---

## 10. File Reference

| File | Purpose |
|------|---------|
| `scripts/lib.sh` | Shared functions: networking, storage detection, recording control |
| `scripts/boot_storage.sh` | SD card bind-mount + stale mount cleanup |
| `scripts/boot_network.sh` | Auto AP/STA state machine (called at boot) |
| `scripts/start_ap.sh` | AP bring-up (driver, hostapd, DHCP) |
| `scripts/stop_ap.sh` | AP teardown (kill processes, clear interface) |
| `scripts/start_sta.sh` | STA bring-up (wpa_supplicant, udhcpc) |
| `scripts/stop_sta.sh` | STA teardown |
| `scripts/control_record.sh` | Recording start/stop/status backend |
| `scripts/device_status.sh` | Network + storage + recording status |
| `scripts/save_wifi.sh` | CGI backend for Wi-Fi credential saving |
| `scripts/save_wifi_args.sh` | Wi-Fi config file writer |
| `scripts/save_wifi_cli.sh` | CLI provisioning helper |
| `scripts/check_wifi_config.sh` | Wi-Fi config existence + validity check |
| `scripts/boot_ap.sh` | Legacy one-shot entry |
| `scripts/start_config_server.sh` | Legacy config server entry |
| `init.d/S97mount_sdcard` | SD card auto-mount at boot |
| `init.d/S98eth0_static` | eth0 static IP (192.168.1.200) |
| `init.d/S99boot_net` | Boot-time network state machine |
| `nginx.conf` | nginx config: port 80 (CGI) + port 8080 (file server) |
| `rkipc.ini` | SDK config: SD card mount path, recording parameters |
| `www/provision.html` | Wi-Fi provisioning form |
| `www/control.html` | Record test/debug page |
| `www/cgi-bin/save_wifi.cgi` | Wi-Fi save CGI entry |
| `www/cgi-bin/status.cgi` | Device status CGI entry |
| `www/cgi-bin/record.cgi` | Record control CGI entry |
| `www/cgi-bin/list` | JSON video list CGI |
| `www/cgi-bin/delete` | File deletion CGI |
| `www/cgi-bin/videos` | HTML video list CGI |