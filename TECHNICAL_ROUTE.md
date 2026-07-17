# Camera Board 技术手册

## 1. 硬件平台

| 组件 | 型号 / 说明 |
|---|---|
| SoC | Rockchip RV1109 / RV1126 |
| Wi-Fi | AIC8800 (BL-M8800DS2)，SDIO 接口，FullMAC 类型 |
| Flash | 内部闪存，/userdata 分区可读写 |
| SD 卡 | /dev/mmcblk0p6 -> /mnt/sdcard（可选） |

### AIC8800 驱动注意事项

该驱动为 FullMAC 类型：Wi-Fi MAC 层在芯片固件中实现，Linux 侧通过 nl80211/cfg80211 与固件通信。

已知问题：当 nl80211 的最后一个用户进程（wpa_supplicant / hostapd）被 SIGTERM 杀死时，驱动可能崩溃。
现象：wlan0 接口消失、ifconfig 找不到、但 /proc/modules 中 aic 模块仍显示已加载。

规避方法（已在 ensure_wifi_driver 中实现）：加载前先 rmmod 清理，清除损坏的内核态状态。
若驱动崩得太彻底（SDIO 设备不响应），需断电重启。

**不要在 prepare_ap_interface 里用 stop_by_pidfile 杀 wpa_supplicant。**
改用 wpa_cli terminate（已在代码中实现）。

---

## 2. 核心脚本

```
/userdata/ap_test/boot_network.sh    顶层入口，由 S99boot_net 调用
/userdata/ap_test/start_ap.sh        顶层 AP 入口
/userdata/ap_test/boot_ap.sh         驱动 + AP 一键启动
/userdata/ap_test/scripts/
  lib.sh            所有脚本 source 的公共函数库
  boot_network.sh   开机网络状态机
  start_sta.sh      STA 模式启动
  start_ap.sh       AP 模式启动
  stop_sta.sh       STA 模式关闭
  stop_ap.sh        AP 模式关闭
  save_wifi.sh      CGI 后端 - 保存 Wi-Fi 配置
  save_wifi_args.sh 写入 wpa_supplicant.conf
  save_wifi_cli.sh  CLI 配网
  reset_wifi.sh     重置 Wi-Fi 配置，切回 AP
  device_status.sh  设备状态查询后端
  control_record.sh 录像控制后端
  check_wifi_config.sh  检查配置是否存在且有效
  boot_storage.sh   SD 卡绑定挂载
```

---

## 3. 开机启动

```
init -> /etc/init.d/rcS
  S97mount_sdcard -> 挂载 SD 卡（若 /dev/mmcblk0p6 存在）
  S98eth0_static  -> eth0 静态 IP 192.168.1.200
  S99boot_net     -> 重试 boot_network.sh 最多 3 次 @ 10s
                      成功后：sed OSD 配置
                      全失败：kill -HUP 1（重启 init）
```

### boot_network.sh 决策

```
setup_sdcard_storage()
  -> SD 卡已挂载 -> bind /mnt/sdcard/record -> /userdata/video0
  -> 无 SD 卡    -> 走内部闪存 /userdata/video0

ensure_wifi_driver()
  -> wlan0 已存在? 直接返回
  -> 不存在:
       rmmod aic8800_fdrv aic8800_bsp cfg80211（清除上次崩溃状态）
       insmod cfg80211.ko -> aic8800_bsp.ko -> aic8800_fdrv.ko
       sleep 2
       wlan0 仍未出现? exit 1

check_wifi_config()?
  有配置 -> start_sta.sh
             成功 -> STA 模式（exit 0）
             失败 -> rm -f 配置 -> start_ap.sh -> AP 模式
  无配置 -> start_ap.sh -> AP 模式
```

---

## 4. STA 模式流程

```
start_sta.sh:
  ensure_wifi_driver()
  check_wifi_config()

  prepare_sta_interface()
    kill_process_if_running hostapd/udhcpd/dnsmasq/httpd/wpa_supplicant/udhcpc
    stop_by_pidfile（所有进程名，含进程名校验）
    clear_iface_addr（ifconfig wlan0 0.0.0.0 down）
    sleep 1
    ifconfig wlan0 up

  start_wpa_supplicant()
    wpa_supplicant -B -i wlan0 -c wpa_supplicant.conf -P pidfile -C /var/run/wpa_supplicant
  sleep 2

  start_udhcpc()
    udhcpc -i wlan0 -b

  wait_for_sta_ip(12)
    每 1 秒检查一次：
      有无 inet addr? -> 成功返回 0
      已跑 5 秒? -> 检查 wpa_cli status:
        COMPLETED / 4WAY_HANDSHAKE / ASSOCIATED / SCANNING 等 -> 继续等待
        DISCONNECTED / INACTIVE -> 密码错误或网络不可用，立即返回 1
    12 秒超时 -> 返回 1

  成功 -> nginx 保活检查 -> exit 0
  失败 -> show_iface_status -> exit 1
```

### 快速失败逻辑

正常连接链路：SCANNING -> AUTHENTICATING -> ASSOCIATING -> ASSOCIATED -> 4WAY_HANDSHAKE -> GROUP_HANDSHAKE -> COMPLETED

第 5 秒起每次循环检查 wpa_cli status，只对 DISCONNECTED / INACTIVE / 空状态快速失败。
4WAY_HANDSHAKE 是正常状态（路由器在验证密码），不误判。

---

## 5. AP 模式流程

```
start_ap.sh:
  ensure_wifi_driver()

  prepare_ap_interface()
    kill_process_if_running wpa_supplicant/hostapd/udhcpd/dnsmasq/httpd
    stop_by_pidfile（hostapd/udhcpd/dnsmasq/httpd/udhcpc，跳过 wpa_supplicant）
    iface_down || true     -> 先关接口
    sleep 2
    wpa_cli -i wlan0 terminate -> 优雅停止 wpa_supplicant（接口已 down，防驱动崩溃）
    sleep 1
    iface_up_with_addr    -> ifconfig wlan0 192.168.4.1 netmask 255.255.255.0 up
    sleep 2

  stabilize_ap_ip()
    循环检查 AP IP 是否稳定，最多 3 次

  write_hostapd_conf()
    从 MAC 后 4 位推导 SSID: CameraBoard_XXXX
    写入运行时 hostapd 配置

  start_hostapd()      hostapd -B -P pidfile hostapd.conf
  start_dhcp_server()  udhcpd 优先 / dnsmasq 备用
```

### SSID 推导规则

```
MAC 地址: 08:0A:12:34:56:78
tr -d ' :' -> 080A12345678
tail -c 5 -> 45678
SSID: CameraBoard_45678
```

环境变量 AP_SSID 可覆盖。

---

## 6. 配网与回退

### 正常配网

```
手机提交正确 Wi-Fi
  -> save_wifi.cgi -> save_wifi.sh
  -> 保存配置到 /userdata/wifi/wpa_supplicant.conf
  -> schedule_sta_after_provision()
      sleep 3
      start_sta.sh -> 连上路由器 -> exit 0
  -> STA 模式
```

### 错误密码回退

```
手机提交错误 Wi-Fi
  -> 同上保存配置
  -> schedule_sta_after_provision()
      sleep 3
      start_sta.sh -> wpa_cli 5s 判断失败 -> exit 1
      -> echo "AP fallback" >> log
      -> rm -f 错误配置（重要：避免开机重试）
      -> start_ap.sh -> AP 模式
  总耗时：约 17 秒
```

### 配网时 AP 消失 -> STA 失败 -> 回退 AP 的时序

```
T=0s   手机提交 Wi-Fi
T=0.1s CGI 返回 OK
T=3s   start_sta.sh 启动
T=3.1s 杀 hostapd  -> 手机断开 AP
T=5-8s wpa_supplicant 尝试连接（错误密码 -> 快速失败）
T=5-8s exit 1
T=5-8s rm -f 配置 + start_ap.sh
T=14s  AP 恢复（手机可重新连接）
```

---

## 7. 进程管理安全机制

### stop_by_pidfile 进程名校验

```sh
stop_by_pidfile "$WPA_SUPPLICANT_PID_FILE" "wpa_supplicant"
```

调用时传第二个参数（预期进程名）。stop_by_pidfile 内部：
1. 读取 PID 文件 -> 得到 PID
2. kill -0 PID 检查进程是否存在
3. 如果给了预期进程名 -> 读 /proc/PID/comm
4. 不匹配 -> 跳过，删 PID 文件（PID 被回收给了别的进程）
5. 匹配 -> kill PID

PID 文件存放在持久化存储（/userdata/ap_test/runtime/），跨重启可能包含过期 PID。
不校验进程名会误杀被回收 PID 的其他进程。

### prepare_ap_interface 不杀 wpa_supplicant

prepare_sta_interface 可以杀 wpa_supplicant（因为杀完后立即启动新的 wpa_supplicant，nl80211 无空窗）。

prepare_ap_interface 不杀 wpa_supplicant（改为 iface_down 后 wpa_cli terminate）。
原因：kill 旧 wpa_supplicant -> nl80211 关闭 -> AIC8800 驱动 stop 回调 -> 可能崩溃。

---

## 8. CRLF 行尾陷阱

Windows 下编辑的 shell 脚本默认 CRLF 行尾。BusyBox sh 无法处理：

- shebang `#!/bin/sh\r` -> 内核找 `/bin/sh\r` -> 不存在 -> "not found"
- `set -e` 下 `\r` 可能导致语法解析异常

修复：sed -i 's/\\r$//' scripts/*.sh

预防：git 配置 core.autocrlf=input 或编辑器设置 LF 行尾。

---

## 9. 录像与存储

### 控制 API

```sh
# 开始
curl -X PUT 'http://<ip>/cgi-bin/entry.cgi/event/start-record?duration=60&stream=0'

# 停止
curl -X PUT 'http://<ip>/cgi-bin/entry.cgi/event/stop-record'

# 状态
curl http://<ip>/cgi-bin/status.cgi
```

### 存储切换

```
SD 卡存在 -> mount --bind /mnt/sdcard/record -> /userdata/video0
SD 卡不在 -> /userdata/video0 走内部闪存
```

文件通过 nginx 8080 端口下载，零拷贝。

### RTSP 预览



```sh
rtsp://<ip>/live/1    # 子码流（640x480，推荐预览）
rtsp://<ip>/live/0    # 主码流（最高 3840x2160）
```

---

## 10. 端口分配

| 端口 | 服务 |
|---|---|
| 80 | nginx - 网页 + CGI |
| 554 | 板子 SDK RTSP 服务器 |
| 1935 | nginx-rtmp RTMP |
| 8080 | nginx - 文件下载 |
| 7000 | UDP 广播（板上无 nc/socat，不可用）|

---

## 11. 已知限制

1. AIC8800 驱动在 nl80211 最后一个用户退出时可能崩溃（已在 ensure_wifi_driver 加 rmmod 防护）
2. 板上无 nc、无 socat -> UDP 广播不可用，App 只能靠子网扫描
3. 无 killall -> kill_process_if_running 静默失败，依赖 stop_by_pidfile 兜底
4. rkipc 每次启动时从出厂模板自动生成 /userdata/rkipc.ini，覆盖之前的修改。
   OSD 预览页字幕设置（[osd.0] [osd.1] 的 enabled = 1）每次都会被还原。
   修复：S99boot_net 在 rkipc 启动之前执行 sed 修改 OSD 配置：
   sed -i '/^\[osd\.0\]/,/^\[osd\.1\]/s/enabled *= *1/enabled = 0/' /userdata/rkipc.ini
   验证：grep -A2 'osd' /userdata/rkipc.ini 应输出 enabled = 0

5. 运行时 WiFi 断开不会自动回退 AP（需加 watchdog）
