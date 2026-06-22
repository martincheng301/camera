#!/bin/sh

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNTIME_DIR=${RUNTIME_DIR:-"$PROJECT_DIR/runtime"}

WLAN_IFACE=${WLAN_IFACE:-wlan0}
AP_IP=${AP_IP:-192.168.4.1}
AP_PREFIX=${AP_PREFIX:-24}
AP_NETMASK=${AP_NETMASK:-255.255.255.0}
AP_SSID=${AP_SSID:-CameraBoard_Setup}
AP_PASSPHRASE=${AP_PASSPHRASE:-12345678}
AP_CHANNEL=${AP_CHANNEL:-6}
DHCP_START=${DHCP_START:-192.168.4.10}
DHCP_END=${DHCP_END:-192.168.4.100}
DHCP_LEASE=${DHCP_LEASE:-43200}
HTTP_PORT=${HTTP_PORT:-80}
WWW_DIR=${WWW_DIR:-"$PROJECT_DIR/www"}
PROVISION_DIR=${PROVISION_DIR:-/userdata/wifi}
RECORD_DIR=${RECORD_DIR:-}
WPA_SUPPLICANT_CONF=${WPA_SUPPLICANT_CONF:-"$PROVISION_DIR/wpa_supplicant.conf"}
PROVISION_STAGING_FILE=${PROVISION_STAGING_FILE:-"$PROVISION_DIR/ap_provision.conf"}
WPA_SUPPLICANT_CTRL_DIR=${WPA_SUPPLICANT_CTRL_DIR:-/var/run/wpa_supplicant}
STA_DHCP_LEASE_FILE=${STA_DHCP_LEASE_FILE:-"$RUNTIME_DIR/udhcpc.leases"}
STA_CONNECT_TIMEOUT=${STA_CONNECT_TIMEOUT:-20}

HOSTAPD_TEMPLATE=${HOSTAPD_TEMPLATE:-"$PROJECT_DIR/conf/hostapd/hostapd.conf"}
DNSMASQ_TEMPLATE=${DNSMASQ_TEMPLATE:-"$PROJECT_DIR/conf/dnsmasq/dnsmasq.conf"}
UDHCPD_TEMPLATE=${UDHCPD_TEMPLATE:-"$PROJECT_DIR/conf/udhcpd/udhcpd.conf"}

HOSTAPD_RUNTIME_CONF="$RUNTIME_DIR/hostapd.conf"
DNSMASQ_RUNTIME_CONF="$RUNTIME_DIR/dnsmasq.conf"
UDHCPD_RUNTIME_CONF="$RUNTIME_DIR/udhcpd.conf"
HOSTAPD_PID_FILE="$RUNTIME_DIR/hostapd.pid"
DNSMASQ_PID_FILE="$RUNTIME_DIR/dnsmasq.pid"
UDHCPD_PID_FILE="$RUNTIME_DIR/udhcpd.pid"
UDHCPD_LEASE_FILE="$RUNTIME_DIR/udhcpd.leases"
HTTPD_PID_FILE="$RUNTIME_DIR/httpd.pid"
WPA_SUPPLICANT_PID_FILE="$RUNTIME_DIR/wpa_supplicant.pid"
UDHCPC_PID_FILE="$RUNTIME_DIR/udhcpc.pid"
RECORD_STATE_FILE="$RUNTIME_DIR/record.state"
RECORD_PID_FILE="$RUNTIME_DIR/record.pid"
PROVISION_STA_LOG="$RUNTIME_DIR/provision_sta.log"
DHCP_BACKEND=""

CFG80211_MODULE=${CFG80211_MODULE:-/oem/usr/ko/cfg80211.ko}
AIC8800_BSP_MODULE=${AIC8800_BSP_MODULE:-/oem/usr/ko/aic8800_bsp.ko}
AIC8800_FDRV_MODULE=${AIC8800_FDRV_MODULE:-/oem/usr/ko/aic8800_fdrv.ko}
RECORD_START_CMD=${RECORD_START_CMD:-}
RECORD_STOP_CMD=${RECORD_STOP_CMD:-}
RECORD_STATUS_CMD=${RECORD_STATUS_CMD:-}
PROVISION_AUTO_STA=${PROVISION_AUTO_STA:-1}
PROVISION_STA_DELAY=${PROVISION_STA_DELAY:-3}

log() {
    printf '%s %s\n' "[ap]" "$*"
}

ensure_runtime_dir() {
    mkdir -p "$RUNTIME_DIR"
}

ensure_runtime_files() {
    ensure_runtime_dir
    : >"$UDHCPD_LEASE_FILE"
    : >"$STA_DHCP_LEASE_FILE"
}

ensure_provision_dir() {
    mkdir -p "$PROVISION_DIR"
}

ensure_wpa_ctrl_dir() {
    mkdir -p "$WPA_SUPPLICANT_CTRL_DIR"
}

kill_process_if_running() {
    proc_name="$1"

    if ! command -v killall >/dev/null 2>&1; then
        return
    fi

    killall "$proc_name" >/dev/null 2>&1 || true
}

require_cmd() {
    cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "missing command: $cmd"
        exit 1
    fi
}

write_hostapd_conf() {
    ensure_runtime_dir
    sed \
        -e "s|@WLAN_IFACE@|$WLAN_IFACE|g" \
        -e "s|@AP_SSID@|$AP_SSID|g" \
        -e "s|@AP_PASSPHRASE@|$AP_PASSPHRASE|g" \
        -e "s|@AP_CHANNEL@|$AP_CHANNEL|g" \
        "$HOSTAPD_TEMPLATE" >"$HOSTAPD_RUNTIME_CONF"
}

write_dnsmasq_conf() {
    ensure_runtime_dir
    sed \
        -e "s|@WLAN_IFACE@|$WLAN_IFACE|g" \
        -e "s|@AP_IP@|$AP_IP|g" \
        -e "s|@DHCP_START@|$DHCP_START|g" \
        -e "s|@DHCP_END@|$DHCP_END|g" \
        "$DNSMASQ_TEMPLATE" >"$DNSMASQ_RUNTIME_CONF"
}

write_udhcpd_conf() {
    ensure_runtime_dir
    sed \
        -e "s|@WLAN_IFACE@|$WLAN_IFACE|g" \
        -e "s|@AP_IP@|$AP_IP|g" \
        -e "s|@AP_NETMASK@|$AP_NETMASK|g" \
        -e "s|@DHCP_START@|$DHCP_START|g" \
        -e "s|@DHCP_END@|$DHCP_END|g" \
        -e "s|@DHCP_LEASE@|$DHCP_LEASE|g" \
        -e "s|@UDHCPD_PID_FILE@|$UDHCPD_PID_FILE|g" \
        -e "s|@UDHCPD_LEASE_FILE@|$UDHCPD_LEASE_FILE|g" \
        "$UDHCPD_TEMPLATE" >"$UDHCPD_RUNTIME_CONF"
}

iface_down() {
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig "$WLAN_IFACE" down
    elif command -v ip >/dev/null 2>&1; then
        ip link set "$WLAN_IFACE" down
    else
        log "missing ifconfig/ip"
        exit 1
    fi
}

iface_up_with_addr() {
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig "$WLAN_IFACE" "$AP_IP" netmask "$AP_NETMASK" up
    elif command -v ip >/dev/null 2>&1; then
        ip addr flush dev "$WLAN_IFACE" || true
        ip addr add "$AP_IP/$AP_PREFIX" dev "$WLAN_IFACE"
        ip link set "$WLAN_IFACE" up
    else
        log "missing ifconfig/ip"
        exit 1
    fi
}

configure_route() {
    if command -v route >/dev/null 2>&1; then
        route add -net 192.168.4.0 netmask "$AP_NETMASK" gw "$AP_IP" dev "$WLAN_IFACE" 2>/dev/null || true
    fi
}

start_hostapd() {
    hostapd -B -P "$HOSTAPD_PID_FILE" "$HOSTAPD_RUNTIME_CONF"
}

start_dnsmasq() {
    dnsmasq --conf-file="$DNSMASQ_RUNTIME_CONF" --pid-file="$DNSMASQ_PID_FILE"
}

start_udhcpd() {
    ensure_runtime_files
    udhcpd -S "$UDHCPD_RUNTIME_CONF" >/dev/null 2>&1 &
    echo "$!" >"$UDHCPD_PID_FILE"
}

start_httpd() {
    if command -v httpd >/dev/null 2>&1; then
        httpd -h "$WWW_DIR" -p "$HTTP_PORT" >/dev/null 2>&1 &
        echo "$!" >"$HTTPD_PID_FILE"
        return 0
    fi

    if [ ! -d "$WWW_DIR" ]; then
        log "missing web root: $WWW_DIR"
        exit 1
    fi

    log "httpd not available, skip config page"
    return 1
}


start_wpa_supplicant() {
    require_cmd wpa_supplicant
    ensure_wpa_ctrl_dir
    ensure_runtime_dir

    wpa_supplicant \
        -B \
        -i "$WLAN_IFACE" \
        -c "$WPA_SUPPLICANT_CONF" \
        -P "$WPA_SUPPLICANT_PID_FILE" \
        -C "$WPA_SUPPLICANT_CTRL_DIR"
}

start_udhcpc() {
    require_cmd udhcpc
    ensure_runtime_files

    udhcpc \
        -i "$WLAN_IFACE" \
        -p "$UDHCPC_PID_FILE" \
        -s /usr/share/udhcpc/default.script \
        -b >/dev/null 2>&1 || true
}

verify_iface_has_ip() {
    if command -v ifconfig >/dev/null 2>&1; then
        if ifconfig "$WLAN_IFACE" | grep -q "$AP_IP"; then
            return 0
        fi
        return 1
    fi

    if command -v ip >/dev/null 2>&1; then
        if ip addr show dev "$WLAN_IFACE" | grep -q "$AP_IP"; then
            return 0
        fi
        return 1
    fi

    return 1
}

ensure_ap_ip() {
    if verify_iface_has_ip; then
        return
    fi

    log "re-applying AP address $AP_IP to $WLAN_IFACE"
    iface_up_with_addr
}

stabilize_ap_ip() {
    attempts=${1:-3}
    delay=${2:-1}
    count=0

    while [ "$count" -lt "$attempts" ]; do
        ensure_ap_ip
        sleep "$delay"

        if verify_iface_has_ip; then
            count=$((count + 1))
            continue
        fi

        log "AP address disappeared after stabilization check, retrying"
        count=$((count + 1))
    done

    ensure_ap_ip
}

show_iface_status() {
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig "$WLAN_IFACE"
        return
    fi

    if command -v ip >/dev/null 2>&1; then
        ip addr show dev "$WLAN_IFACE"
    fi
}

show_http_status() {
    log "config page: http://$AP_IP:$HTTP_PORT/"
}

wait_for_sta_ip() {
    timeout="$1"
    count=0

    while [ "$count" -lt "$timeout" ]; do
        if command -v ifconfig >/dev/null 2>&1; then
            if ifconfig "$WLAN_IFACE" | grep -q "inet addr:"; then
                return 0
            fi
        elif command -v ip >/dev/null 2>&1; then
            if ip addr show dev "$WLAN_IFACE" | grep -q "inet "; then
                return 0
            fi
        fi

        sleep 1
        count=$((count + 1))
    done

    return 1
}

check_wifi_config() {
    if [ ! -f "$WPA_SUPPLICANT_CONF" ]; then
        log "missing Wi-Fi config: $WPA_SUPPLICANT_CONF"
        return 1
    fi

    if ! grep -q 'ssid="' "$WPA_SUPPLICANT_CONF"; then
        log "invalid Wi-Fi config: missing ssid"
        return 1
    fi

    return 0
}

prepare_sta_interface() {
    log "cleaning AP-side processes before STA"
    kill_process_if_running hostapd
    kill_process_if_running udhcpd
    kill_process_if_running dnsmasq
    kill_process_if_running httpd
    kill_process_if_running wpa_supplicant
    kill_process_if_running udhcpc

    stop_by_pidfile "$HOSTAPD_PID_FILE"
    stop_by_pidfile "$UDHCPD_PID_FILE"
    stop_by_pidfile "$DNSMASQ_PID_FILE"
    stop_by_pidfile "$HTTPD_PID_FILE"
    stop_by_pidfile "$WPA_SUPPLICANT_PID_FILE"
    stop_by_pidfile "$UDHCPC_PID_FILE"

    clear_iface_addr
    sleep 1

    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig "$WLAN_IFACE" up
    elif command -v ip >/dev/null 2>&1; then
        ip link set "$WLAN_IFACE" up
    fi
}

show_wifi_config_summary() {
    if [ -f "$PROVISION_STAGING_FILE" ]; then
        log "using saved Wi-Fi config:"
        cat "$PROVISION_STAGING_FILE"
    fi
}

load_module_if_needed() {
    module_path="$1"
    module_name=$(basename "$module_path" .ko)

    if grep -q "^$module_name " /proc/modules 2>/dev/null; then
        return
    fi

    if [ ! -f "$module_path" ]; then
        log "missing module: $module_path"
        exit 1
    fi

    log "loading module $module_name"
    insmod "$module_path"
}

ensure_wifi_driver() {
    if [ -d "/sys/class/net/$WLAN_IFACE" ]; then
        return
    fi

    if [ -f "$CFG80211_MODULE" ]; then
        load_module_if_needed "$CFG80211_MODULE"
    fi

    load_module_if_needed "$AIC8800_BSP_MODULE"
    load_module_if_needed "$AIC8800_FDRV_MODULE"

    sleep 2

    if [ ! -d "/sys/class/net/$WLAN_IFACE" ]; then
        log "wireless interface $WLAN_IFACE not found after loading modules"
        exit 1
    fi
}

prepare_ap_interface() {
    log "cleaning conflicting wifi processes"
    kill_process_if_running wpa_supplicant
    kill_process_if_running hostapd
    kill_process_if_running udhcpd
    kill_process_if_running dnsmasq
    kill_process_if_running httpd

    log "resetting interface $WLAN_IFACE"
    iface_down || true
    sleep 2
    iface_up_with_addr
    sleep 2
}

pick_dhcp_backend() {
    if command -v udhcpd >/dev/null 2>&1; then
        DHCP_BACKEND="udhcpd"
        return
    fi

    if command -v dnsmasq >/dev/null 2>&1; then
        DHCP_BACKEND="dnsmasq"
        return
    fi

    log "missing DHCP server: need udhcpd or dnsmasq"
    exit 1
}

start_dhcp_server() {
    pick_dhcp_backend

    if [ "$DHCP_BACKEND" = "udhcpd" ]; then
        write_udhcpd_conf
        log "launching udhcpd"
        start_udhcpd
        return
    fi

    write_dnsmasq_conf
    log "launching dnsmasq"
    start_dnsmasq
}

stop_by_pidfile() {
    pid_file="$1"
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file" 2>/dev/null || true)
        if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
        fi
        rm -f "$pid_file"
    fi
}

clear_iface_addr() {
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig "$WLAN_IFACE" 0.0.0.0 down || true
    elif command -v ip >/dev/null 2>&1; then
        ip addr flush dev "$WLAN_IFACE" || true
        ip link set "$WLAN_IFACE" down || true
    fi
}

get_network_mode() {
    if verify_iface_has_ip; then
        printf 'ap'
        return
    fi

    if command -v ifconfig >/dev/null 2>&1; then
        if ifconfig "$WLAN_IFACE" | grep -q "inet addr:"; then
            printf 'sta'
            return
        fi
    elif command -v ip >/dev/null 2>&1; then
        if ip addr show dev "$WLAN_IFACE" | grep -q "inet "; then
            printf 'sta'
            return
        fi
    fi

    printf 'idle'
}

get_iface_ipv4() {
    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig "$WLAN_IFACE" | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' | head -n 1
        return
    fi

    if command -v ip >/dev/null 2>&1; then
        ip -4 addr show dev "$WLAN_IFACE" | sed -n 's/.*inet \([0-9.]*\)\/.*/\1/p' | head -n 1
    fi
}

is_recording() {
    if [ -f "$RECORD_PID_FILE" ]; then
        pid=$(cat "$RECORD_PID_FILE" 2>/dev/null || true)
        if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        rm -f "$RECORD_PID_FILE"
    fi

    [ -f "$RECORD_STATE_FILE" ] && grep -q '^recording=1$' "$RECORD_STATE_FILE"
}

write_record_state() {
    state="$1"
    ensure_runtime_dir
    printf 'recording=%s\n' "$state" >"$RECORD_STATE_FILE"
}

start_recording() {
    ensure_runtime_dir

    if is_recording; then
        log "recording already active"
        return 0
    fi

    if [ -n "$RECORD_START_CMD" ]; then
        log "starting recording with custom command"
        sh -c "$RECORD_START_CMD" >/dev/null 2>&1 &
        echo "$!" >"$RECORD_PID_FILE"
    fi

    write_record_state 1
}

stop_recording() {
    if [ -n "$RECORD_STOP_CMD" ]; then
        log "stopping recording with custom command"
        sh -c "$RECORD_STOP_CMD" >/dev/null 2>&1 || true
    fi

    stop_by_pidfile "$RECORD_PID_FILE"
    write_record_state 0
}

get_recording_status() {
    if [ -n "$RECORD_STATUS_CMD" ]; then
        sh -c "$RECORD_STATUS_CMD"
        return
    fi

    if is_recording; then
        printf 'recording'
        return
    fi

    printf 'idle'
}

schedule_sta_after_provision() {
    if [ "$PROVISION_AUTO_STA" != "1" ]; then
        log "auto STA switch after provisioning is disabled"
        return 0
    fi

    ensure_runtime_dir
    log "scheduling STA switch ${PROVISION_STA_DELAY}s after provisioning"

    (
        sleep "$PROVISION_STA_DELAY"
        if "$PROJECT_DIR/scripts/start_sta.sh" >"$PROVISION_STA_LOG" 2>&1; then
            exit 0
        fi
        echo "AP fallback: STA connect failed, restarting AP mode" >>"$PROVISION_STA_LOG"
        "$PROJECT_DIR/scripts/start_ap.sh" >>"$PROVISION_STA_LOG" 2>&1
    ) </dev/null >/dev/null 2>&1 &
}

detect_storage() {
    if grep -qs ' /mnt/sdcard ' /proc/mounts && [ -d /mnt/sdcard/record ]; then
        RECORD_DIR=/mnt/sdcard/record
    else
        RECORD_DIR=/userdata/video0
    fi
}

ensure_record_dir() {
    mkdir -p /userdata/video0
    mkdir -p /mnt/sdcard/record
}

setup_sdcard_storage() {
    ensure_record_dir

    if grep -qs ' /mnt/sdcard ' /proc/mounts; then
        log "SD card detected at /mnt/sdcard"
        # Clean any stale mount on /userdata/video0 first
        if mountpoint -q /userdata/video0 2>/dev/null; then
            log "clearing stale mount on /userdata/video0"
            umount /userdata/video0
        fi
        log "bind-mounting /mnt/sdcard/record to /userdata/video0"
        mount --bind /mnt/sdcard/record /userdata/video0
    else
        log "SD card not detected"
        # Remove stale bind mount so /userdata/video0 reverts to internal flash
        if mountpoint -q /userdata/video0 2>/dev/null; then
            log "removing stale bind mount from /userdata/video0"
            umount /userdata/video0
        fi
    fi

    detect_storage
    log "active recording directory: $RECORD_DIR"
}

broadcast_sta_ip() {
    ip_addr=$(get_iface_ipv4)
    if [ -z "$ip_addr" ]; then
        return 1
    fi
    msg="CameraBoard:$ip_addr"
    if command -v nc >/dev/null 2>&1; then
        printf '%s' "$msg" | nc -u -w1 255.255.255.255 7000 >/dev/null 2>&1 || true
        log "broadcasted STA IP $ip_addr to UDP 7000"
    elif command -v socat >/dev/null 2>&1; then
        printf '%s' "$msg" | socat - UDP-DATAGRAM:255.255.255.255:7000,broadcast
        log "broadcasted STA IP $ip_addr via socat"
    else
        log "no nc or socat, skipping UDP broadcast"
    fi
}
