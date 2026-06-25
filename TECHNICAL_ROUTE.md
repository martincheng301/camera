# Camera Board Functional Reference

Interface and behaviour reference for handover / app integration.
Organised by feature, not by development stage.

---

## 1. Wi-Fi Driver Load

**What:** Load AIC8800 kernel modules so wlan0 appears.

**Modules:** /oem/usr/ko/cfg80211.ko, /oem/usr/ko/aic8800_bsp.ko, /oem/usr/ko/aic8800_fdrv.ko

**Script:** lib.sh → ensure_wifi_driver().  Called by every network script at startup; idempotent (skips if wlan0 already exists).

---

## 2. AP Mode

**What:** Board creates hotspot CameraBoard_Setup with DHCP so a phone can connect.

**Trigger:**

- Boot without saved Wi-Fi config, OR
- STA connect fails → fallback to AP, OR
- Manual: sh /userdata/ap_test/boot_network.sh

**Network defaults:**

| Item | Value |
|------|-------|
| SSID | CameraBoard_Setup |
| Passphrase | 12345678 |
| Board IP | 192.168.4.1 |
| Netmask | 255.255.255.0 |
| DHCP range | 192.168.4.10 - 192.168.4.100 |
| Channel | 6 |

**Technical flow:**
`
boot_network.sh / start_ap.sh
  │
  ├─ ensure_wifi_driver()          — load AIC8800 modules if wlan0 missing
  ├─ kill conflicting processes    — wpa_supplicant, hostapd, udhcpd, dnsmasq
  ├─ reset wlan0                   — down, sleep 2s, up
  ├─ iface_up_with_addr()          — assign 192.168.4.1
  ├─ start_hostapd()               — hostapd -B -P runtime/hostapd.pid runtime/hostapd.conf
  ├─ stabilize_ap_ip()             — re-apply IP if driver cleared it during AP mode switch
  └─ start_dhcp_server()           — udhcpd preferred, dnsmasq fallback
`

**Key files:** scripts/start_ap.sh, scripts/stop_ap.sh, conf/hostapd/hostapd.conf, conf/udhcpd/udhcpd.conf

---

## 3. Wi-Fi Provisioning

**What:** Phone sends router SSID + password to board while connected to camera AP.

**Entry point:**
`
GET http://192.168.4.1/cgi-bin/save_wifi.cgi?ssid=<SSID>&psk=<PASSWORD>
`
| Field | Description |
|-------|-------------|
| Method | **GET** (query string) |
| ssid | Target router SSID |
| psk | Router password (min 8 chars; omit for open networks) |
| Response | OK: saved Wi-Fi config for SSID=<ssid> |
| Response (fail) | ERROR: ... |

**Technical flow:**
`
GET /cgi-bin/save_wifi.cgi?ssid=X&psk=Y
  │
  └─ nginx → fcgiwrap → /oem/usr/www/cgi-bin/save_wifi.cgi
       │
       └─ exec /userdata/ap_test/scripts/save_wifi.sh
            │
            ├─ validate ssid present, psk length >= 8 if set
            ├─ save_wifi_args.sh  →  write /userdata/wifi/wpa_supplicant.conf
            ├─ print "OK" response
            └─ schedule_sta_after_provision()  →  sleep 3s → start_sta.sh
`

**Output files:**

| File | Purpose |
|------|---------|
| /userdata/wifi/wpa_supplicant.conf | wpa_supplicant config (ctrl_interface + network block) |
| /userdata/wifi/ap_provision.conf | Plaintext staging copy (SSID=... PSK=...) |

**CGI Content-Type rule:** All CGI shell scripts must output Content-Type header BEFORE set -eu and BEFORE sourcing dependencies. Failure to do so → nginx returns 502 with no visible error.

---

## 4. STA Mode

**What:** Board stops AP, joins target router as a Wi-Fi client, obtains IP via DHCP.

**Trigger:**

- Scheduled automatically 3 s after provisioning (schedule_sta_after_provision)
- Boot with saved config present (oot_network.sh → check_wifi_config() → start_sta.sh)
- Manual: sh /userdata/ap_test/scripts/start_sta.sh

**Technical flow:**
`
start_sta.sh
  │
  ├─ check_wifi_config()            — verify /userdata/wifi/wpa_supplicant.conf exists and has ssid=
  ├─ prepare_sta_interface()        — kill AP processes (hostapd, udhcpd, dnsmasq), clear wlan0 addr
  ├─ start_wpa_supplicant()         — wpa_supplicant -B -i wlan0 -c wpa_supplicant.conf
  ├─ start_udhcpc()                 — udhcpc -i wlan0 -p pidfile -s /usr/share/udhcpc/default.script -b
  ├─ wait_for_sta_ip(20)            — poll ifconfig/ip for inet addr up to 20 s
  └─ broadcast_sta_ip()             — send CameraBoard:IP to UDP 255.255.255.255:7000
`

**Key files:** scripts/start_sta.sh, scripts/stop_sta.sh

---

## 5. UDP Device Discovery(not available at RV1126B)

**What:** After STA connect, board broadcasts its LAN IP so app can discover it without scanning.

**Broadcast target:** 255.255.255.255:7000 (UDP)
**Message format:** CameraBoard:<IP> (e.g. CameraBoard:192.168.1.105)
**Timing:** Immediately after wait_for_sta_ip() succeeds in start_sta.sh
**Transport:** 
c -u -w1 255.255.255.255 7000 (BusyBox nc) or socat fallback.  Skips silently if neither available.

**App-side integration:**
- Open a UDP socket, bind to port 7000
- Parse incoming datagrams as UTF-8 string
- Split on : — part after first colon is the board IP

---

## 6. Boot-Time Network State Machine

**What:** At power-on, decide whether to enter AP or STA mode automatically.

**Init integration:** /etc/rcS.d/S99boot_net → /userdata/ap_test/boot_network.sh

**Boot order:**
`
S97mount_sdcard   — mount SD card if /dev/mmcblk0p6 exists
S98eth0_static    — set eth0 to 192.168.1.200 (if interface exists)
S99boot_net       — run boot_network.sh
`

**Decision logic in oot_network.sh:**
`
boot_network.sh
  ├─ setup_sdcard_storage()     — bind-mount SD card → /userdata/video0 if present
  ├─ ensure_wifi_driver()
  └─ check_wifi_config()?
       ├─ yes → start_sta.sh
       │         ├─ success → done (STA mode)
       │         └─ fail    → start_ap.sh (fallback)
       └─ no  → start_ap.sh (AP mode)
`

---

## 7. eth0 Static IP(for testing)

**What:** Wired Ethernet gets fixed IP 192.168.1.200 at boot for debug/backup access.

**Script:** init.d/S98eth0_static → ifconfig eth0 192.168.1.200 netmask 255.255.255.0 up
**Idempotent:** Only runs if /sys/class/net/eth0 exists.

---

## 8. Recording Control

**What:** Start, stop, or query recording via HTTPS API.  Uses board-native SDK endpoints.

### Start recording
`
PUT http://<board-ip>/cgi-bin/entry.cgi/event/start-record
`
| Field | Description |
|-------|-------------|
| Method | **PUT** |
| duration | Recording length in seconds (optional) |
| stream | Stream index: 0 = mainStream, 1 = subStream (optional) |
| Response | {} on success |

### Stop recording
`
PUT http://<board-ip>/cgi-bin/entry.cgi/event/stop-record
`
| Field | Description |
|-------|-------------|
| Method | **PUT** |
| Response | {} on success |

### Recording status (shell wrapper)
`
GET http://<board-ip>/cgi-bin/status.cgi
`
Returns: 
ecording=recording|idle

### Video parameter configuration
`
PUT http://<board-ip>/cgi-bin/entry.cgi/video/0
Content-Type: application/json

{"sResolution":"3840*2160","sOutputDataType":"H.265","iMaxRate":8192,...}
`
| Field | Description |
|-------|-------------|
| Method | **PUT** |
| Body | JSON string; all fields optional; full schema in 
kipc.ini [capability.video] |
| Response | {} on success |

### Available parameters (main stream, stream 0)

| Parameter | Type | Allowed values |
|-----------|------|----------------|
| sResolution | string | 3840*2160, 2880*1616, 1920*1080, 1280*720, 960*540, 640*360, 320*240 |
| sOutputDataType | string | H.264, H.265 |
| sRCMode | string | CBR, VBR |
| sRCQuality | string | lowest, lower, low, medium, high, higher, highest |
| sSmart | string | open, close |
| sGOPMode | string | normalP, smartP |
| sStreamType | string | mainStream, subStream |
| iMaxRate | number | 256, 512, 1024, 2048, 3072, 4096, 6144, 8192, 12288, 16384 |
| iGOP | number | 1-400 |
| iStreamSmooth | number | 1-100 |
| sFrameRate | string | 1/2, 1, 2, 4, 6, 8, 10, 12, 14, 15, 16, 18, 20, 25, 30 |

s-prefixed keys are string values (quoted in JSON). i-prefixed keys are number values (unquoted). Send only parameters you want to change.

| Response | `{}` on success |


**Legacy wrapper:** GET /cgi-bin/record.cgi?action=start|stop|status also works (calls control_record.sh).
Prefer the native PUT endpoints above.

---

## 9. Storage Management

**What:** Recordings go to SD card (/mnt/sdcard/record) when present, fall back to internal flash (/userdata/video0).

### Architecture
`
Boot:   setup_sdcard_storage()
          │
          ├─ SD mounted? → mount --bind /mnt/sdcard/record → /userdata/video0
          └─ No         → /userdata/video0 stays on internal flash

Runtime: detect_storage()
           │
           ├─ /proc/mounts has /mnt/sdcard? → RECORD_DIR=/mnt/sdcard/record
           └─ No                            → RECORD_DIR=/userdata/video0
`

### Component paths
| Component | Path | Notes |
|-----------|------|-------|
| nginx port 8080 | /userdata/video0 | Fixed root; bind-mounted to SD at boot if present |
| CGI scripts | $RECORD_DIR (dynamic) | Resolved by detect_storage() in lib.sh |
| SDK recording target | /mnt/sdcard/record | Controlled by 
kipc.ini [storage.0].folder_name=record |

### Fallback behaviour
| SD card state | /userdata/video0 | CGI RECORD_DIR |
|---------------|---------------------|------------------|
| Mounted at boot | bind mount → SD | /mnt/sdcard/record |
| Absent at boot | internal flash dir | /userdata/video0 |
| Removed after boot | internal flash (stale mount cleaned up) | /userdata/video0 |

### Manual storage recovery
`sh
sh /userdata/ap_test/scripts/boot_storage.sh
`

### Storage status
`sh
GET /cgi-bin/status.cgi
# Returns:  storage=/mnt/sdcard/record  or  /userdata/video0
#           storage_dev=sdcard  or  internal
`

### SDK config (
kipc.ini)
`ini
[storage]
mount_path                     = /mnt/sdcard
dev_path                       = /dev/mmcblk0p6

[storage.0]
enable                         = 0          ; ← set to 1 when ready to record
folder_name                    = record
file_format                    = mp4
file_duration                  = 60
`

---

## 10. Video File Listing

### JSON listing
`
GET http://<board-ip>/cgi-bin/list
`
| Field | Description |
|-------|-------------|
| Method | **GET** |
| Response | JSON |

Response format:
`json
{
  "dir": "/mnt/sdcard/record",
  "recording": false,
  "files": [
    {"name": "20260616_143000.mp4", "size": 52428800, "mtime": 1687435200},
    ...
  ]
}
`
| Field | Type | Description |
|-------|------|-------------|
| dir | string | Current recording directory (resolved by detect_storage()) |
| recording | bool | Whether a recording is in progress (checks open FD in dir) |
| files[].name | string | Filename |
| files[].size | integer | File size in bytes |
| files[].mtime | integer | Modification time as Unix timestamp |

### HTML listing
`
GET http://<board-ip>/cgi-bin/videos
`
Returns HTML page with clickable download links (auto-refresh 10 s).  Links point to http://<board-ip>:8080/<filename>.

---

## 11. Video File Download

`
GET http://<board-ip>:8080/<filename>
`
| Field | Description |
|-------|-------------|
| Method | **GET** |
| Port | **8080** (separate nginx server block) |
| Root | /userdata/video0 (bind-mounted to SD at boot if present) |
| Transport | Zero-copy via nginx sendfile on |

No directory listing on this port — use /cgi-bin/list or /cgi-bin/videos for file discovery.

---

## 12. Video File Deletion

`
POST http://<board-ip>/cgi-bin/delete?name=<filename>
`
| Field | Description |
|-------|-------------|
| Method | **POST** |
| name | Filename to delete (no path separators allowed) |
| Response (ok) | {"ok":true} |
| Response (fail) | {"ok":false,"error":"..."} |

Safety: blocks filenames containing /, \, or .. to prevent path-traversal.

---

## 13. RTSP Live Preview

`
rtsp://<board-ip>/live/1
rtsp://<board-ip>/live/0
`
| Stream | Resolution |
|--------|-----------|
| /live/0 | Main stream (up to 3840x2160) |
| /live/1 | Sub stream (640x480) |

Served by the board SDK's RTSP server (port 554).  Not part of nginx.

---

## 14. Device Status

`
GET http://<board-ip>/cgi-bin/status.cgi
`
Response:
`
mode=ap|sta|idle
ip=<IPv4 address or empty>
recording=recording|idle
storage=/mnt/sdcard/record|/userdata/video0
storage_dev=sdcard|internal
`

---

## 15. HTTP Endpoint Summary

| Method | Path | Port | Description |
|--------|------|------|-------------|
| GET | /cgi-bin/save_wifi.cgi?ssid=&psk= | 80 | Wi-Fi provisioning |
| GET | /cgi-bin/list | 80 | JSON video file list |
| GET | /cgi-bin/videos | 80 | HTML video file list |
| GET | /cgi-bin/status.cgi | 80 | Device status |
| GET | /cgi-bin/record.cgi?action=start\|stop\|status | 80 | Recording control (legacy wrapper) |
| GET | /<filename> | 8080 | Raw file download |
| PUT | /cgi-bin/entry.cgi/event/start-record | 80 | Start recording (native) |
| PUT | /cgi-bin/entry.cgi/event/stop-record | 80 | Stop recording (native) |
| PUT | /cgi-bin/entry.cgi/video/0 | 80 | Configure video parameters (JSON body) |
| POST | /cgi-bin/delete?name= | 80 | Delete a recording |
| POST | /cgi-bin/reset.cgi | 80 | Reset Wi-Fi config and switch to AP mode |
| — |
tsp://<ip>/live/1 | 554 | RTSP sub-stream preview |
| — | UDP 255.255.255.255:7000 | 7000 | STA IP broadcast after connect |

---

## 16. Port Assignment

| Port | Service |
|------|---------|
| 80 | nginx — web pages, CGI (fcgiwrap) |
| 554 | Board SDK RTSP server |
| 1935 | Board SDK RTMP (nginx-rtmp) |
| 8080 | nginx — raw video file download |
| 7000 | UDP broadcast — STA device discovery |

---

## 17. Deployment from Factory Board

Full step-by-step guide is in [README.md](README.md), Section 3.  Quick summary:

`sh
# Push files
adb push scripts    /userdata/ap_test/
adb push conf       /userdata/ap_test/
adb push init.d     /userdata/ap_test/
adb push boot_network.sh boot_ap.sh start_ap.sh /userdata/ap_test/
adb push nginx.conf /oem/usr/etc/nginx/nginx.conf
adb push rkipc.ini  /oem/usr/etc/rkipc.ini
adb push www/control.html www/provision.html /oem/usr/www/
adb push www/cgi-bin/* /oem/usr/www/cgi-bin/

# Set permissions
chmod +x /userdata/ap_test/scripts/*.sh /userdata/ap_test/boot_*.sh /userdata/ap_test/start_ap.sh
chmod +x /userdata/ap_test/init.d/*
chmod +x /oem/usr/www/cgi-bin/*

# Register boot scripts
ln -sf /userdata/ap_test/init.d/S97mount_sdcard /etc/rcS.d/S97mount_sdcard
ln -sf /userdata/ap_test/init.d/S98eth0_static  /etc/rcS.d/S98eth0_static
ln -sf /userdata/ap_test/init.d/S99boot_net     /etc/rcS.d/S99boot_net

# Reload nginx, reboot
nginx -s reload
reboot
`

