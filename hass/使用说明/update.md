## Home Assistant 升级脚本设计规范 (`update.sh`)

> 脚本路径:
> `/data/data/com.termux/files/home/servicemanager/hass/update.sh`

> 适用场景:
>
> * 手动或自动更新 Home Assistant 版本
> * 支持升级和降级

2025.7.1, 升级依赖 pip install click==8.1.7
---

### 1. 功能概览

| 步骤      | 操作说明                                                                         |
| ------- | ---------------------------------------------------------------------------- |
| 配置版本    | 从 `TARGET_VERSION` 环境变量，或脚本第一个参数解析版本                                         |
| 进入容器    | `proot-distro login ubuntu << EOF` 执行升级操作                                    |
| 升级操作    | activate venv + ensurepip + pip + HA pip upgrade                             |
| 版本验证    | 执行 `hass --version` 确认更新成功                                                   |
| 日志输出    | 写入 `/data/data/com.termux/files/home/servicemanager/hass/logs/update.log`    |
| MQTT 上报 | topic: `isg/update/hass/status` ：`updating` → `success` / `failed` + message |

---

### 2. 执行示例

```bash
# 指定环境变量
TARGET_VERSION=2025.7.1 bash update.sh

# 或指定参数
bash update.sh 2025.7.1
```

---

### 3. 升级脚本代码

```bash
proot-distro login ubuntu << 'EOF'

log_step() {
  echo -e "\n[STEP] \$1"
}

log_step "激活虚拟环境"
source /root/homeassistant/bin/activate

log_step "确保 ensurepip 可用"
python -m ensurepip --upgrade

log_step "升级 pip"
pip install --upgrade pip

log_step "升级 Home Assistant 到 \$TARGET_VERSION"
pip install --upgrade homeassistant==\$TARGET_VERSION || exit 1

log_step "验证 HA 版本"
hass --version || exit 1

log_step "✅ 升级完成"
EOF
```

---

### 4. 环境变量

| 名称               | 默认值                      | 说明          |
| ---------------- | ------------------------ | ----------- |
| `PROOT_DISTRO`   | `ubuntu`                 | Proot 容器名称  |
| `BACKUP_DIR`     | `/sdcard/isgbackup/hass` | 日志输出目录      |
| `TARGET_VERSION` | *(required)*             | 指定更新的 HA 版本 |

---

### 5. MQTT 成功示例

```json
{
  "service": "hass",
  "status": "success",
  "version": "2025.7.1",
  "log": "/data/data/com.termux/files/home/servicemanager/hass/logs/update.log",
  "timestamp": 1720574500
}
```

---

### 6. 设计要点

* 支持命令行参数和环境变量，便于自动更新脚本调用
* 配合 MQTT 进行可视化状态上报
* 日志和错误描述统一保存，便于排查
* 升级前推荐执行 backup.sh 备份
* 升级成功后可选重启或触发 autocheck 系列脚本

---

> 推荐配合 `autocheck.sh` 自动检测 + 更新，或系统升级前手动执行


MQTT 上报统一采用
load_mqtt_conf() {
  MQTT_HOST=$(grep -Po '^[[:space:]]*host:[[:space:]]*\K.*' "$CONFIG_FILE" | head -n1)
  MQTT_PORT=$(grep -Po '^[[:space:]]*port:[[:space:]]*\K.*' "$CONFIG_FILE" | head -n1)
  MQTT_USER=$(grep -Po '^[[:space:]]*username:[[:space:]]*\K.*' "$CONFIG_FILE" | head -n1)
  MQTT_PASS=$(grep -Po '^[[:space:]]*password:[[:space:]]*\K.*' "$CONFIG_FILE" | head -n1)
}

mqtt_report() {
  local topic="$1"
  local payload="$2"
  load_mqtt_conf
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$topic" -m "$payload" || true
  echo "[MQTT] $topic -> $payload" >> "$LOG_FILE"
}





## Home Assistant 升级脚本使用说明 (`update.sh`)提示词

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/update.sh`

> **脚本功能**
>
> * 将 `/root/homeassistant` 虚拟环境中的 Home Assistant 升级或降级到 **指定版本**。
> * **版本号来源**：`TARGET_VERSION` 环境变量，或脚本第一个参数。
> * 日志: 所有输出写入独立日志，日志存入/data/data/com.termux/files/home/servicemanager/<service_id>/logs/<script>.log, 保存最近500条
> * 通过termux Mosquitto cli 上报 MQTT，主题：isg/update/hass/status `updating` → `success` / `failed`。
> * MQTT broker信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml获取
> * 错误消息：通过MQTT message上报，message为英文
> * 通过环境参数可以指定升级的版本
> * 升级后需要使用stop.sh停止homeassistant, start.sh开启homeassistant, 最后使用status.sh来判断HA是否运行起来，正常运行后才能判断为success
> * 升级脚本
>
```bash
proot-distro login ubuntu << 'EOF'

log_step() {
  echo -e "\n[STEP] $1"
}

log_step "激活虚拟环境"
source /root/homeassistant/bin/activate

log_step "升级 ensurepip（确保 pip 可用）"
python -m ensurepip --upgrade

log_step "升级 pip"
pip install --upgrade pip
pip install click==8.1.7

log_step "升级 Home Assistant 到 2025.7.1"
pip install --upgrade homeassistant==2025.7.1

log_step "验证版本"
hass --version

log_step "✅ 升级完成"

EOF
```

增加校验：若未设置 TARGET_VERSION 环境变量，则立即：
打印错误，上报 MQTT 状态 failed
脚本中止，不再进入 proot 升级逻辑
现在必须这样运行：
TARGET_VERSION=2025.7.1 bash update.sh
否则脚本将拒绝执行，避免出现 homeassistant== 的错误命令。还需验证版本号格式或校验升级是否成功

升级后，第一次启动会比较久，需要“等待直到启动成功或超时”策略
如果最后超时，启动失败，需要MQTT发升级失败的消息
