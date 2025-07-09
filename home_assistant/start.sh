#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 启动脚本（后台运行 + 上报 MQTT online）
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
FLAG_FILE="/data/data/com.termux/files/home/services/$SERVICE_ID/.disabled"
LOG_DIR="/sdcard/isgbackup/ha"
LOG_FILE="$LOG_DIR/start_$(date +'%Y%m%d-%H%M%S').log"
MQTT_TOPIC="isg/services/$SERVICE_ID/status"

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

log "删除 disable flag: $FLAG_FILE"
rm -f "$FLAG_FILE"

# 启动服务
log "启动 Home Assistant..."
proot-distro login ubuntu -- bash -c "cd ~ && source homeassistant/bin/activate && nohup hass > /dev/null 2>&1 &"

# 等待几秒再确认状态
sleep 5
status=$(bash /data/data/com.termux/files/home/services/home_assistant/status.sh --quiet || true)
if [[ "$status" == "running" ]]; then
  log "服务状态确认: $status ✅"
  log "上报 MQTT 状态为 online..."
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASSWORD" -t "$MQTT_TOPIC" -m "online" -r
else
  log "服务状态异常: $status ⚠️"
fi

log "启动流程结束"
exit 0
