## Home Assistant 安装脚本使用说明 (`uninstall.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/uninstall.sh`

> **运行目标**
# 职责：
#   1. 调用 stop.sh 终止所有 hass 进程
#   2. 删除虚拟环境 /root/homeassistant 及配置目录 /root/.homeassistant
#   3. 写 uninstall_<timestamp>.log 到 /sdcard/isgbackup/ha/
#   4. 创建 .disabled 标志，阻止 autocheck.sh 误重装/重启
#   5. 通过termux Mosquitto cli 上报 MQTT，主题：isg/install/hass/status uninstalling → uninstalled / failed。
---
