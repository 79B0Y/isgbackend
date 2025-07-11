## Home Assistant 卸载脚本设计规范 (`uninstall.sh`)

> 脚本路径:
> `/data/data/com.termux/files/home/servicemanager/hass/uninstall.sh`

> 适用场景:
>
> * 需要手动或配合 autocheck 重新安装的时候
> * 执行完全卸载、清理环境、禁止自动重启

---

### 1. 功能概览

| 步骤           | 操作说明                                                                                      |
| ------------ | ----------------------------------------------------------------------------------------- |
| 停止服务         | 调用 `stop.sh`，确保服务已停止                                                                      |
| 进入容器         | 通过 `proot-distro login ubuntu << EOF` 执行内部卸载                                              |
| 卸载 HA        | activate venv 后，pip uninstall homeassistant                                               |
| 删除 venv      | 删除 `/root/homeassistant`                                                                  |
| 删除配置         | 删除 `/root/.homeassistant`                                                                 |
| 日志输出         | 写入 `/data/data/com.termux/files/home/servicemanager/hass/logs/uninstall.log`              |
| 创建 .disabled | 防止 autocheck.sh 重装/重启                                                                     |
| MQTT 上报      | topic: `isg/install/hass/status`，包括 `uninstalling` → `uninstalled` / `failed` + `message` |

---

### 2. 执行流程

```bash
# 调用 stop.sh 停止服务
bash stop.sh

# 进入容器执行内容
proot-distro login ubuntu << 'EOF'
log_step() {
  echo -e "\n[STEP] \$1"
}

log_step "🧹 停止 Home Assistant 进程"
HASS_PID=\$(pgrep -f "homeassistant/bin/python3 .*hass") && kill "\$HASS_PID" || echo "[INFO] 无需终止"

log_step "卸载 Home Assistant"
source /root/homeassistant/bin/activate && pip uninstall -y homeassistant || echo "[INFO] HA 未安装"

log_step "删除虚拟环境"
rm -rf /root/homeassistant

log_step "清理配置目录"
rm -rf /root/.homeassistant

log_step "卸载完成 ✅"
EOF

# 创建 disabled 标志
touch /data/data/com.termux/files/home/servicemanager/hass/.disabled

# 上报 MQTT
mqtt_report "isg/install/hass/status" '{"status": "uninstalled", "message": "Home Assistant completely removed."}'
```

---

### 3. 日志管理

* 日志输入: `uninstall.log`
* 最多保留 500 条，超过自动删除
* 错误上报英文 message ，便于前端读取

---

### 4. 设计要点

* 全量删除虚拟环境 + 配置文件，确保安装环境稳定
* 先停止服务，避免进程死链或文件占用
* `.disabled` 标志配合 autocheck 停止手动重启
* 适配日志和 MQTT 解耦方便 Web/App 后端管理

---

> 推荐配合 `install.sh` 重装时先执行本脚本，确保环境重置。



## Home Assistant 卸载脚本使用说明 (`uninstall.sh`)提示词

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/uninstall.sh`

> **运行目标**
# 职责：
#   1. 调用 stop.sh 停止home assistant
#   2. 进入proot ubuntu容器，卸载home assistant
proot-distro login ubuntu << 'EOF'

log_step() {
  echo -e "\n[STEP] $1"
}

log_step "🧹 停止 Home Assistant 进程"
HASS_PID=\$(pgrep -f "homeassistant/bin/python3 .*hass") && kill "\$HASS_PID" || echo "[INFO] 无需终止，未检测到运行中的 Home Assistant"

log_step "卸载 Home Assistant"
source /root/homeassistant/bin/activate && pip uninstall -y homeassistant || echo "[INFO] Home Assistant 未安装"

log_step "删除虚拟环境 /root/homeassistant"
rm -rf /root/homeassistant

log_step "清理配置文件目录 /root/.homeassistant"
rm -rf /root/.homeassistant

log_step "卸载完成 ✅"

EOF

#   3. 日志: 所有输出写入独立日志，日志存入/data/data/com.termux/files/home/servicemanager/<service_id>/logs/<script>.log, 保存最近500条
#   4. 创建 .disabled 标志，阻止 autocheck.sh 误重装/重启
#   5. 通过termux Mosquitto cli 上报 MQTT，主题：isg/install/hass/status uninstalling → uninstalled / failed。
#。 6. 错误消息：通过MQTT message上报，message为英文
---
