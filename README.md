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
| SD   | Optional 閳?`/dev/mmcblk0p6` auto-mounted to `/mnt/sdcard` |

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
閳规壕鏀㈤埞鈧?boot_network.sh          # Top-level boot entry (auto AP/STA)
閳规壕鏀㈤埞鈧?boot_ap.sh               # One-shot AP entry
閳规壕鏀㈤埞鈧?start_ap.sh              # AP entry (driver + start)
閳规壕鏀㈤埞鈧?nginx.conf               # nginx config (port 80 CGI + 8080 file server)
閳规壕鏀㈤埞鈧?rkipc.ini                # SDK recording config (folder_name=record)
閳?閳规壕鏀㈤埞鈧?scripts/
閳?  閳规壕鏀㈤埞鈧?lib.sh               # Shared helpers (network, recording, storage)
閳?  閳规壕鏀㈤埞鈧?boot_storage.sh      # SD card bind-mount setup
閳?  閳规壕鏀㈤埞鈧?boot_network.sh      # Auto network state-machine
閳?  閳规壕鏀㈤埞鈧?start_ap.sh          # AP bring-up
閳?  閳规壕鏀㈤埞鈧?stop_ap.sh           # AP teardown
閳?  閳规壕鏀㈤埞鈧?start_sta.sh         # STA bring-up
閳?  閳规壕鏀㈤埞鈧?stop_sta.sh          # STA teardown
閳?  閳规壕鏀㈤埞鈧?boot_ap.sh           # Driver + AP one-shot
閳?  閳规壕鏀㈤埞鈧?control_record.sh    # Record start/stop/status backend
閳?  閳规壕鏀㈤埞鈧?device_status.sh     # Network + recording + storage status
閳?  閳规壕鏀㈤埞鈧?save_wifi.sh         # CGI backend for Wi-Fi provisioning
閳?  閳规壕鏀㈤埞鈧?save_wifi_args.sh    # Wi-Fi config writer
閳?  閳规壕鏀㈤埞鈧?save_wifi_cli.sh     # CLI provisioning helper
閳?  閳规壕鏀㈤埞鈧?check_wifi_config.sh # Config existence check
閳?  閳规柡鏀㈤埞鈧?start_config_server.sh  # Config page server (legacy)
閳?閳规壕鏀㈤埞鈧?init.d/
閳?  閳规壕鏀㈤埞鈧?S97mount_sdcard      # SD card auto-mount
閳?  閳规壕鏀㈤埞鈧?S98eth0_static       # eth0 static IP (192.168.1.200)
閳?  閳规柡鏀㈤埞鈧?S99boot_net          # Retry boot_network.sh 3x @10s; OSD sed; kill -HUP 1 on failure
閳?閳规壕鏀㈤埞鈧?conf/
閳?  閳规壕鏀㈤埞鈧?hostapd/hostapd.conf     # AP template
閳?  閳规壕鏀㈤埞鈧?udhcpd/udhcpd.conf       # DHCP template (preferred)
閳?  閳规柡鏀㈤埞鈧?dnsmasq/dnsmasq.conf     # DHCP fallback template
閳?閳规柡鏀㈤埞鈧?www/
    閳规壕鏀㈤埞鈧?control.html          # Record test page
    閳规壕鏀㈤埞鈧?provision.html        # Wi-Fi provisioning form
    閳规柡鏀㈤埞鈧?cgi-bin/
        閳规壕鏀㈤埞鈧?save_wifi.cgi     # Wi-Fi save endpoint
        閳规壕鏀㈤埞鈧?status.cgi        # Device status endpoint
        閳规壕鏀㈤埞鈧?record.cgi        # Record control endpoint
        閳规壕鏀㈤埞鈧?list              # Video file JSON listing
        閳规壕鏀㈤埞鈧?delete            # Video file deletion
        閳规柡鏀㈤埞鈧?videos            # Video file HTML listing
```

---

## 3. From a Factory Board

### 3.1 閳?Get shell access

Connect via serial (115200 baud) or ADB:

```sh
adb shell
# or
screen /dev/ttyUSB0 115200
```

### 3.2 閳?Verify board tools

```sh
which nginx
which fcgiwrap
which hostapd
which wpa_supplicant
which udhcpd
which ifconfig
```

Any missing tool needs to be added to the board firmware build.

### 3.3 閳?Create project directory

```sh
mkdir -p /userdata/ap_test
```

### 3.4 閳?Push all files

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
adb push www/cgi-bin/reset.cgi      /oem/usr/www/cgi-bin/
adb push www/cgi-bin/save_wifi.cgi  /oem/usr/www/cgi-bin/
adb push www/cgi-bin/status.cgi     /oem/usr/www/cgi-bin/
adb push www/cgi-bin/record.cgi     /oem/usr/www/cgi-bin/
adb push www/cgi-bin/list           /oem/usr/www/cgi-bin/
adb push www/cgi-bin/delete         /oem/usr/www/cgi-bin/
adb push www/cgi-bin/videos         /oem/usr/www/cgi-bin/
```

### 3.5 閳?Set permissions

```sh
chmod +x /userdata/ap_test/scripts/*.sh
chmod +x /userdata/ap_test/boot_*.sh
chmod +x /userdata/ap_test/start_ap.sh
chmod +x /userdata/ap_test/init.d/*.sh
chmod +x /oem/usr/www/cgi-bin/*
```

### 3.6 閳?Start nginx + fcgiwrap

```sh
# Ensure nginx is running
if ! ps | grep -q '[n]ginx'; then
    nginx
fi
nix -s reload

# Ensure fcgiwrap is running
if ! ps | grep -q '[f]cgiwrap'; then
    fcgiwrap -s unix:/run/fcgiwrap.sock &
fi
```

### 3.7a 閳?Test AP manually before reboot

# Do NOT reboot yet. Test AP startup first:
```sh
cd /userdata/ap_test
sh boot_network.sh
# Expected: logs show [ap] AP-ENABLED, [ap] AP ready
# Phone should see CameraBoard_Setup

# If AP fails, diagnose:
ifconfig wlan0                          # wlan0 exists and has 192.168.4.1?
ps | grep hostapd                       # hostapd running?
ps | grep udhcpd                        # dhcp server running?
ps | grep nginx                         # nginx running?
```

### 3.7 閳?Register boot scripts

Copy the init.d scripts into `/etc/init.d/` so `rcS` runs them at
boot.  (This board uses BusyBox init with `/etc/init.d/rcS`; symlinks
do not work because `/userdata` may not be mounted yet when rcS runs.)

```sh
cp /userdata/ap_test/init.d/S97mount_sdcard /etc/init.d/
cp /userdata/ap_test/init.d/S98eth0_static  /etc/init.d/
cp /userdata/ap_test/init.d/S99boot_net     /etc/init.d/
chmod +x /etc/init.d/S97mount_sdcard /etc/init.d/S98eth0_static /etc/init.d/S99boot_net
```

### 3.8 閳?Configure SD card auto-mount (optional)

If the board does not auto-mount the SD card, add an `/etc/fstab` entry:

```sh
echo '/dev/mmcblk0p6  /mnt/sdcard  auto  defaults  0  0' >> /etc/fstab
```

Verify the block device name:

```sh
ls -l /dev/mmcblk*
```

### 3.9 閳?Reboot and verify

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
  閳?  閳规壕鏀?/etc/rcS.d/S97mount_sdcard   閳?mount SD card if present
  閳规壕鏀?/etc/rcS.d/S98eth0_static    閳?set eth0 IP (192.168.1.200)
  閳规柡鏀?/etc/rcS.d/S99boot_net
       閳?       閳规柡鏀?/userdata/ap_test/boot_network.sh
            閳?            閳规壕鏀?setup_sdcard_storage()    閳?bind-mount SD 閳?/userdata/video0
            閳?                             falls back to internal flash
            閳?            閳规柡鏀?check saved Wi-Fi config?
                 閳规壕鏀?yes 閳?start_sta.sh    閳?join router
                 閳?        閳规壕鏀?success 閳?done (STA mode)
                 閳?        閳规柡鏀?fail    閳?start_ap.sh (fallback)
                 閳规柡鏀?no  閳?start_ap.sh    閳?AP mode (CameraBoard_Setup)
```

Two boot modes:

| Mode | Trigger | Phone action |
|------|---------|--------------|
| AP   | No saved Wi-Fi config | Connect to `CameraBoard_Setup`, open `http://192.168.4.1` |
| STA  | Saved config exists | S99 retry 3x @ 10s; on failure kill -HUP 1 restarts init | Find board on LAN |

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
         閳?         閳规壕鏀?SD card mounted? 閳光偓閳光偓Yes閳光偓閳光偓閳?mount --bind /mnt/sdcard/record
         閳?                                     /userdata/video0
         閳规柡鏀?No 閳光偓閳光偓閳?/userdata/video0 stays on internal flash

Runtime:  detect_storage()
            閳?            閳规壕鏀?/proc/mounts has /mnt/sdcard?
            閳?   閳规柡鏀?Yes 閳光偓閳光偓閳?RECORD_DIR=/mnt/sdcard/record
            閳规柡鏀?No 閳光偓閳光偓閳?RECORD_DIR=/userdata/video0
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

### Port 80 閳?nginx + fcgiwrap

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

### Port 8080 閳?nginx raw file server

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
- [ ] No saved config 閳?AP visible (`CameraBoard_Setup`)
- [ ] Saved config 閳?STA connects to router
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
| `init.d/S99boot_net` | Retry boot_network.sh 3x @10s; OSD sed; kill -HUP 1 on failure |
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
