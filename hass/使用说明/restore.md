## Home Assistant 还原脚本设计规范 (`restore.sh`)

> 脚本路径:
> `/data/data/com.termux/files/home/servicemanager/hass/restore.sh`

> 适用环境:
>
> * Termux + Proot Ubuntu
> * Home Assistant 数据还原操作

指定还原
RESTORE_FILE=/sdcard/isgbackup/hass/specific_backup.zip bash restore.sh

---

### 1. 功能概览

| 步骤        | 操作内容                                                                       |
| --------- | -------------------------------------------------------------------------- |
| 先备份       | 执行 `backup.sh`，如失败则继续选择旧备份                                                 |
| 还原选择      | 自动选择最新 backup.tar.gz，或指定路径                                                 |
| 压缩格式      | 如非 .tar.gz，而是 .zip ，则先解压后重新压缩为 tar.gz                                      |
| 系统操作      | 停止服务，清空配置，解压还原，重启                                                          |
| 日志输出      | 写入 `/data/data/com.termux/files/home/servicemanager/hass/logs/restore.log` |
| MQTT 上报   | 上报为 `isg/restore/hass/status` ，包括 `restoring` → `success` / `failed`       |
| Broker 配置 | 从 `configuration.yaml` 读取 MQTT 信息                                          |

---

### 2. 执行流程

```bash
# 1. 先备份，确保可回滚
bash backup.sh || echo "[WARN] 备份失败，继续还原"

# 2. 选择备份文件
若指定路径：检查 *.tar.gz 格式，非 tar.gz 则异常上报
如为 zip 文件： unzip 后重压缩为 .tar.gz

# 3. 还原操作
- 停止服务
- 清空 /root/.homeassistant
- 解压 tar.gz 文件
- 重启服务

# 4. 日志 + MQTT 上报
```

---

### 3. 环境变量

| 名称             | 默认值                      | 说明         |
| -------------- | ------------------------ | ---------- |
| `PROOT_DISTRO` | `ubuntu`                 | Proot 容器名称 |
| `BACKUP_DIR`   | `/sdcard/isgbackup/hass` | 备份文件默认目录   |
| `RESTORE_FILE` | *(optional)*             | 指定备份文件路径   |

---

### 4. MQTT 成功上报示例

```json
{
  "service": "hass",
  "status": "success",
  "file": "/sdcard/isgbackup/hass/homeassistant_backup_20250710-030000.tar.gz",
  "log": "/data/data/com.termux/files/home/servicemanager/hass/logs/restore.log",
  "timestamp": 1720575060
}
```

---

### 5. 设计要点

* 基于 tar.gz 格式统一备份管理，支持 zip 格式选项
* 自动定位最新 backup\_日期.tar.gz，确保最大化数据恢复
* 返回日志低促化反复，配合 `autocheck.sh` 重试启动
* 通过 MQTT 进行可视化进度显示，便于前端管理同步

---

> 推荐配合升级或卸载前执行还原，确保 HA 环境维持最佳状态


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



## Home Assistant 还原脚本说明 (`restore.sh`)提示词

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/restore.sh`

> **脚本功能**
>
> * 在执行还原前先运行 `backup.sh` 生成最新备份，以防回滚失败导致数据丢失，如果备份失败，则直接选取最新备份
> * 从 **最新备份** `homeassistant_backup_*.tar.gz` 还原 Home Assistant 配置；若无备份则使用 `homeassistant_original.tar.gz`。
> * 自动停止服务 → 清空配置 → 解压备份 → 重启服务。
> * 通过termux Mosquitto cli 上报 MQTT, 主题：isg/restore/hass/status `restoring` → `success` / `failed`。
> * MQTT broker：登陆信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml 获取
> * 错误消息：通过MQTT message上报，message为英文
> * 日志: 所有输出写入独立日志，日志存入/data/data/com.termux/files/home/servicemanager/hass/logs/restore.log, 保存最近500条
> * 环境变量：可以指定备份的文件路径，从指定的路径进行备份，如果指定的文件格式不是*.tar.gz,MQTT上报错误。如果是zip压缩文件，则先将文件解压，然后再压缩成*.tar.gz文件，最后进行还原
> * 还原完成之后，需要使用stop.sh, start.sh, 重启HA系统，查看status，如果显示running，这个时候才显示success，中间过程的status需要通过MQTT上报
> * 成功 MQTT 示例：
```json
{
  "service":"hass",
  "status":"success",
  "file":"/sdcard/isgbackup/hass/homeassistant_backup_20250710-030000.tar.gz",
  "log":"/data/data/com.termux/files/home/servicemanager/hass/logs/restore.log",
  "timestamp":1720575060
}
```
