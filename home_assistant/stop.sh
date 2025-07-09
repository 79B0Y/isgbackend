#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 停止脚本（直接杀掉进程 + 上报 MQTT offline）
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
FLAG_FILE="/data/data/com.termux/files/home/services/$SERVICE_ID/.disabled"
LOG_DIR="/sdcard/isgbackup/ha"
LOG_FILE="$LOG_DIR/stop_$(date +'%Y%m%d-%H%M%S').log"
MQTT_TOPIC="$SERVICE_ID/status"

# 从配置文件中读取 MQTT 参数
CONFIG_FILE="/data/data/com.termux/files/home/services/configuration.yaml"
if [[ -f "$CONFIG_FILE" ]]; then
  MQTT_HOST=$(grep '^mqtt_host:' "$CONFIG_FILE" | awk '{print $2}')
  MQTT_PORT=$(grep '^mqtt_port:' "$CONFIG_FILE" | awk '{print $2}')
  MQTT_USER=$(grep '^mqtt_user:' "$CONFIG_FILE" | awk '{print $2}')
  MQTT_PASSWORD=$(grep '^mqtt_password:' "$CONFIG_FILE" | awk '{print $2}')
else
  MQTT_HOST="127.0.0.1"
  MQTT_PORT=1883
  MQTT_USER="admin"
  MQTT_PASSWORD="admin"
fi

log() {
  echo "[INFO] $1" | tee -a "$LOG_FILE"
}

mkdir -p "$LOG_DIR"
log "日志文件: $LOG_FILE"

log "创建 disable flag: $FLAG_FILE"
touch "$FLAG_FILE"

# 尝试杀死进程（两种常见匹配方式）
log "尝试杀掉进程..."
pkill -f "[h]omeassistant" || pkill -f "[h]ass" || true

log "上报 MQTT 状态为 offline..."
mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASSWORD" -t "$MQTT_TOPIC" -m "offline" -r

log "完成服务停止 ✅"
