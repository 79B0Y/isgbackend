#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 运行状态检查脚本（进程 + 端口 + MQTT Online）
# 保存路径：/data/data/com.termux/files/home/services/home_assistant/status.sh
# ------------------------------------------------------------
# 逻辑：
#   1) 进程是否存在（PID / pgrep）
#   2) 8123 端口是否可达
#   3) MQTT Topic `homeassistant/status` 是否为 online（读取保留消息）
#
# 输出 / 返回值：
#   running  → exit 0  （全部 OK）
#   starting → exit 2  （进程 OK，但端口或 MQTT 未就绪）
#   stopped  → exit 1  （服务未安装或进程不存在）
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
PROOT_DISTRO="${PROOT_DISTRO:-ubuntu}"
PID_FILE="/var/run/${SERVICE_ID}.pid"

# 关键可执行文件（容器内）
HA_MAIN="${HA_MAIN:-/usr/local/bin/hass}"
HA_PORT="${HA_PORT:-8123}"

# MQTT 参数（与 monitor.py / 环境变量保持一致）
MQTT_HOST="${MQTT_HOST:-127.0.0.1}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USER:-admin}"
MQTT_PASS="${MQTT_PASS:-admin}"
MQTT_TOPIC="homeassistant/status"

in_proot() { proot-distro exec "$PROOT_DISTRO" -- "$@"; }

# ------------------------------------------------------------
# 1. 安装 & 进程检查
# ------------------------------------------------------------
if ! in_proot test -x "$HA_MAIN"; then
  echo "stopped"; exit 1
fi

PROC_OK=0
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE"); if ps -p "$PID" > /dev/null 2>&1; then PROC_OK=1; fi
fi
if [ "$PROC_OK" -eq 0 ] && pgrep -f "[h]ass" > /dev/null 2>&1; then PROC_OK=1; fi
[ "$PROC_OK" -eq 0 ] && { echo "stopped"; exit 1; }

# ------------------------------------------------------------
# 2. 端口检查
# ------------------------------------------------------------
PORT_OK=0
if command -v nc >/dev/null 2>&1; then
  nc -z 127.0.0.1 "$HA_PORT" && PORT_OK=1
else
  curl -fsS --max-time 2 "http://127.0.0.1:${HA_PORT}/" >/dev/null 2>&1 && PORT_OK=1
fi

# ------------------------------------------------------------
# 3. MQTT Online 检测（可选）
# ------------------------------------------------------------
MQTT_OK=0
if command -v mosquitto_sub >/dev/null 2>&1; then
  MSG=$(mosquitto_sub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
                      -t "$MQTT_TOPIC" -C 1 -W 2 2>/dev/null || true)
  [[ "$MSG" =~ online ]] && MQTT_OK=1
else
  MQTT_OK=1  # 未安装 mosquitto_sub 时跳过 MQTT 检测
fi

# ------------------------------------------------------------
# 4. 综合判定 & 输出
# ------------------------------------------------------------
if [ "$PORT_OK" -eq 1 ] && [ "$MQTT_OK" -eq 1 ]; then
  echo "running"; exit 0
else
  echo "starting"; exit 2
fi

