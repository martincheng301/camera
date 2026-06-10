# BusyBox AP Test Program

This scaffold is adjusted for embedded boards running BusyBox.

## Purpose

Bring up a Wi-Fi AP so a phone can:

- discover the hotspot
- connect to the board
- receive an IP address
- reach the board at `192.168.4.1`

## Layout

- `boot_network.sh`: top-level auto network entry
- `start_ap.sh`: top-level entry point
- `boot_ap.sh`: one-shot entry for driver + AP
- `scripts/boot_network.sh`: Stage 5 auto boot state machine
- `scripts/start_ap.sh`: start AP
- `scripts/boot_ap.sh`: load AIC8800 modules then start AP
- `scripts/save_wifi.sh`: save Wi-Fi provisioning data
- `scripts/save_wifi_cli.sh`: save Wi-Fi provisioning data from shell
- `scripts/start_config_server.sh`: start config page only
- `scripts/stop_ap.sh`: stop AP
- `scripts/lib.sh`: shared helpers
- `conf/hostapd/hostapd.conf`: hostapd template
- `conf/udhcpd/udhcpd.conf`: BusyBox DHCP template
- `conf/dnsmasq/dnsmasq.conf`: fallback DHCP template
- `www/index.html`: provisioning page
- `www/cgi-bin/save_wifi.cgi`: CGI entry
- `runtime/`: generated configs and pid files

## Expected tools on board

- `hostapd`
- `ifconfig`
- `route`
- `udhcpd` preferred, or `dnsmasq` as fallback
- `httpd`

## Default network

- interface: `wlan0`
- board IP: `192.168.4.1`
- netmask: `255.255.255.0`
- SSID: `CameraBoard_Setup`
- passphrase: `12345678`

## Deploy on board

Copy this directory to a writable path, for example:

```sh
mkdir -p /userdata/ap_test
```

Copy all files under this project into `/userdata/ap_test`.

Then:

```sh
chmod +x /userdata/ap_test/start_ap.sh
chmod +x /userdata/ap_test/scripts/*.sh
```

## Run

Automatic network selection:

```sh
cd /userdata/ap_test
sh ./boot_network.sh
```

Behavior:

1. load AIC8800 modules if needed
2. check whether saved Wi-Fi config exists
3. if config exists, try STA first
4. if STA fails, fall back to AP
5. if config is missing, start AP directly

Manual AP-only startup:

```sh
cd /userdata/ap_test
sh ./boot_ap.sh
```

If the AP starts correctly, the phone should see `CameraBoard_Setup`.

The startup flow is:

1. load AIC8800 modules if `wlan0` is missing
2. stop conflicting processes such as `wpa_supplicant`
3. reset `wlan0`
4. assign `192.168.4.1`
5. start `hostapd`
6. start `udhcpd`
7. start `httpd`

## Stop

```sh
cd /userdata/ap_test
./scripts/stop_ap.sh
```

## Provisioning output

Provisioning writes:

```sh
/userdata/wifi/ap_provision.conf
/userdata/wifi/wpa_supplicant.conf
```

If `httpd` is not available on the board, use CLI provisioning:

```sh
sh /userdata/ap_test/scripts/save_wifi_cli.sh TestAP 12345678
```

## Override defaults

You can override values at runtime:

```sh
WLAN_IFACE=wlan1 AP_SSID=Board_Test AP_PASSPHRASE=87654321 ./start_ap.sh
```

## Before testing

Check these commands on the board:

```sh
ifconfig -a
which hostapd
which udhcpd
which dnsmasq
```

If `udhcpd` exists, the script will use it first.

## AIC8800 defaults

This scaffold assumes these module paths:

```sh
/oem/usr/ko/cfg80211.ko
/oem/usr/ko/aic8800_bsp.ko
/oem/usr/ko/aic8800_fdrv.ko
```

If your board uses different paths, override them at runtime:

```sh
CFG80211_MODULE=/path/cfg80211.ko \
AIC8800_BSP_MODULE=/path/aic8800_bsp.ko \
AIC8800_FDRV_MODULE=/path/aic8800_fdrv.ko \
sh ./boot_ap.sh
```
