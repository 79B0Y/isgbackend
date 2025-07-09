#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 状态检测脚本（使用 mosquitto_sub 查询 MQTT 状态）
# ------------------------------------------------------------
set -euo pipefail

PORT=${PORT:-8123}
CONFIG_FILE="/data/data/com.termux/files/home/services/configuration.yaml"

# 从配置文件中读取 MQTT 参数（必须提前存在）
if [[ -f "$CONFIG_FILE" ]]; then
  MQTT_HOST=$(grep '^mqtt_host:' "$CONFIG_FILE" | awk '{print $2}')
  MQTT_PORT=$(grep '^mqtt_port:' "$CONFIG_FILE" | awk '{print $2}')
  MQTT_USER=$(grep '^mqtt_user:' "$CONFIG_FILE" | awk '{print $2}')
  MQTT_PASSWORD=$(grep '^mqtt_password:' "$CONFIG_FILE" | awk '{print $2}')
else
  echo "[status] 未找到配置文件 $CONFIG_FILE，使用默认参数" >&2
  MQTT_HOST=${MQTT_HOST:-127.0.0.1}
  MQTT_PORT=${MQTT_PORT:-1883}
  MQTT_USER=${MQTT_USER:-admin}
  MQTT_PASSWORD=${MQTT_PASSWORD:-admin}
fi

MQTT_TOPIC="home_assistant/status"

log() {
  echo "[status] $1" >&2
}

status="stopped"; code=1; pid="null"
log "开始状态检查..."

# 1) 进程检查
if pid=$(pgrep -f "[h]omeassistant" | head -n1); then
  log "发现进程 PID: $pid"

  # 2) 端口检查
  if curl -s --head --request GET "http://127.0.0.1:$PORT" | grep -qE "200 OK|302 Found"; then
    log "端口 $PORT 可达，尝试使用 mosquitto_sub 检查 MQTT 状态..."

    mqtt_status=$(mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASSWORD" -t "$MQTT_TOPIC" -C 1 -W 2 2>/dev/null || echo "")
    log "MQTT 返回: $mqtt_status"

    if [[ "$mqtt_status" == "online" ]]; then
      status="running"; code=0
      log "状态: running ✅"
    else
      status="starting"; code=2
      log "状态: starting（MQTT 不是 online）⚠️"
    fi
  else
    status="starting"; code=2
    log "状态: starting（端口 $PORT 不可达）⚠️"
  fi
else
  status="stopped"; code=1
  log "状态: stopped（未检测到 Home Assistant 进程）❌"
fi

case "${1:-}" in
  --json) printf '{"status":"%s","pid":%s}\n' "$status" "$pid";;
  --quiet) ;;
  *) echo "$status";;
esac

exit $code
