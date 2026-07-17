# Camera Board 部署指南

## 1. 项目概况

Rockchip RV1109/RV1126 IP 摄像头主板 + AIC8800 Wi-Fi 模组（SDIO 接口），运行 BusyBox + nginx。

主要功能：
- Wi-Fi 配网（AP 热点接收配置 + STA 连接路由器）
- 录像控制（SDK API：start/stop/status）
- RTSP 实时预览
- 文件管理（list/download/delete）
- SD 卡自动挂载与存储切换

### 网络默认值

| 参数 | AP 模式（配网） | STA 模式（正常使用） |
|------|----------------|-------------------|
| SSID | CameraBoard_ + MAC 后 4 位 | 路由器分配 IP |
| 本机 IP | 192.168.4.1 | 路由器 DHCP |
| 密码 | 12345678 | - |
| DHCP | 192.168.4.10 - 100 | 路由器分配 |

### 板上已验证工具

nginx + fcgiwrap、hostapd、wpa_supplicant、wpa_cli、udhcpd/dnsmasq、udhcpc、ifconfig/ip

---

## 2. 目录结构

```
/userdata/ap_test/
  boot_network.sh     # 开机网络状态机入口
  boot_ap.sh          # AP 一键启动
  start_ap.sh         # AP 启动（驱动 + hostapd）
  nginx.conf          # nginx 配置
  rkipc.ini           # 录像 SDK 配置
  scripts/
    lib.sh            # 公共函数库（所有脚本 source 这个）
    boot_storage.sh   # SD 卡绑定挂载
    boot_network.sh   # 网络状态机（开机调用）
    start_ap.sh       # AP 启动
    stop_ap.sh        # AP 关闭
    start_sta.sh      # STA 启动
    stop_sta.sh       # STA 关闭
    control_record.sh # 录像控制
    device_status.sh  # 设备状态
    save_wifi.sh      # Wi-Fi 配网后端
    save_wifi_args.sh # Wi-Fi 配置文件写入
    save_wifi_cli.sh  # CLI 配网
    reset_wifi.sh     # 重置 Wi-Fi
    check_wifi_config.sh # 配置检查
  conf/
    hostapd/hostapd.conf  # AP 模板
    udhcpd/udhcpd.conf    # DHCP 模板
    dnsmasq/dnsmasq.conf  # DHCP 备用模板
  init.d/
    S97mount_sdcard   # 开机挂载 SD 卡
    S98eth0_static    # 开机 eth0 静态 IP
    S99boot_net       # 开机网络（重试 boot_network.sh 3 次）
  runtime/            # PID 文件 / 日志 / DHCP 租约
  www/
    provision.html    # Wi-Fi 配网页
    control.html      # 录像调试页
    cgi-bin/          # CGI 脚本
```

---

## 3. 从零部署

### 3.1 获取 shell

```sh
adb shell
# 或串口
screen /dev/ttyUSB0 115200
```

### 3.2 确认工具

```sh
which nginx fcgiwrap hostapd wpa_supplicant udhcpd ifconfig wpa_cli
```

### 3.3 创建目录

```sh
mkdir -p /userdata/ap_test
```

### 3.4 推送文件（从电脑执行）

```sh
# 脚本 + 配置
adb push scripts    /userdata/ap_test/
adb push conf       /userdata/ap_test/
adb push init.d     /userdata/ap_test/

# 入口脚本
adb push boot_network.sh /userdata/ap_test/
adb push boot_ap.sh      /userdata/ap_test/
adb push start_ap.sh     /userdata/ap_test/

# nginx
adb push nginx.conf /oem/usr/etc/nginx/nginx.conf

# rkipc
adb push rkipc.ini  /oem/usr/etc/rkipc.ini

# 网页
adb push www/control.html   /oem/usr/www/
adb push www/provision.html /oem/usr/www/

# CGI
adb push www/cgi-bin/* /oem/usr/www/cgi-bin/
```

### 3.5 权限 + 注册开机

```sh
chmod +x /userdata/ap_test/scripts/*.sh
chmod +x /userdata/ap_test/boot_*.sh
chmod +x /userdata/ap_test/start_ap.sh
chmod +x /userdata/ap_test/init.d/*.sh
chmod +x /oem/usr/www/cgi-bin/*

cp /userdata/ap_test/init.d/S97mount_sdcard /etc/init.d/
cp /userdata/ap_test/init.d/S98eth0_static  /etc/init.d/
cp /userdata/ap_test/init.d/S99boot_net     /etc/init.d/
chmod +x /etc/init.d/S9[7-9]*
```

### 3.6 启动 nginx + fcgiwrap

```sh
if ! ps | grep -q '[n]ginx'; then nginx; fi
if ! ps | grep -q '[f]cgiwrap'; then
    fcgiwrap -s unix:/run/fcgiwrap.sock &
fi
```

### 3.7 重启验证

```sh
reboot
# 检查
mount | grep sdcard
ps | grep nginx
ps | grep hostapd
ifconfig wlan0
```

---

## 4. 启动流程

```
开机 -> rcS
  S97mount_sdcard        -> 挂载 SD 卡
  S98eth0_static         -> eth0 静态 IP
  S99boot_net (最多重试 3 次 @ 10s)
    -> /userdata/ap_test/boot_network.sh
      -> setup_sdcard_storage()   绑定 SD 卡到 /userdata/video0
      -> ensure_wifi_driver()     加载 AIC8800 驱动
      -> check_wifi_config()?
         有配置 -> start_sta.sh -> 连路由器
                   成功 -> STA 模式
                   失败 -> 删错误配置 -> start_ap.sh -> AP 模式
         无配置 -> start_ap.sh -> AP 模式（等待配网）
```

---

## 5. 配网流程（APP内）

1. 手机点击配网按钮，连接 CameraBoard_XXXX（密码 12345678）
2. 手机APP内自动打开 http://192.168.4.1
3. 输入路由器 SSID + 密码
4. 主板保存配置，切 STA
5. 手机切回路由器 Wi-Fi
6. App 子网扫描 -> HTTP 探测 -> 找到主板

### 错误密码的回退

```
提交错误配置
  -> 12 秒后 STA 失败
  -> wpa_cli 大约 5 秒提前判断密码错误（快速失败）
  -> 删除错误配置
  -> 启动 AP 模式（用户可以重新配网）
```

---

## 6. HTTP API

| 方法 | 路径 | 说明 |
|--------|------|------|
| GET | /cgi-bin/status.cgi | 设备状态 |
| GET | /cgi-bin/list | JSON 文件列表 |
| GET | /cgi-bin/videos | HTML 文件列表 |
| GET | /cgi-bin/record.cgi?action=start/stop/status | 录像控制 |
| POST | /cgi-bin/delete?name=<file> | 删除录像 |
| POST | /cgi-bin/reset.cgi | 重置配置，切回 AP |
| PUT | /cgi-bin/entry.cgi/event/start-record | 开始录像（SDK 原生） |
| PUT | /cgi-bin/entry.cgi/event/stop-record | 停止录像 |
| PUT | /cgi-bin/entry.cgi/video/0 | 设置录像参数 |
| GET | http://<ip>:8080/<file> | 下载录像 |
| RTSP | rtsp://<ip>/live/1 | RTSP 子码流预览 |

---

## 7. 故障排查

### wlan0 消失

原因：AIC8800 驱动在 wpa_supplicant 被 kill 时崩溃。

恢复：
```sh
rmmod aic8800_fdrv aic8800_bsp cfg80211
insmod /oem/usr/ko/cfg80211.ko
insmod /oem/usr/ko/aic8800_bsp.ko
insmod /oem/usr/ko/aic8800_fdrv.ko
sleep 2
ifconfig wlan0 up
```

开机 ensure_wifi_driver() 会自动做 rmmod 清理后再加载。如果仍然不行，断电重启。

### 脚本报 "not found"

原因：Windows CRLF 行尾。

修复：
```sh
for f in /userdata/ap_test/scripts/*.sh; do sed -i 's/\r$//' "$f"; done
```

### AP 起不来

```sh
cat /tmp/s99_diag                           # 开机日志
cat /userdata/ap_test/runtime/provision_sta.log  # 配网日志
ifconfig wlan0
ps | grep hostapd
```

### nginx 502

```sh
ps | grep fcgiwrap
ls -l /run/fcgiwrap.sock
```
CGI 脚本必须在 set -eu 之前先输出 Content-Type 头。

### 录像不出现

```sh
curl http://127.0.0.1/cgi-bin/status.cgi  # 看 storage 路径
ls -l /userdata/video0
