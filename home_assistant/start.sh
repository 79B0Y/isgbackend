#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 启动脚本
# 路径：/data/data/com.termux/files/home/services/home_assistant/start.sh
# 作用：
#   • 在 proot-distro 容器后台启动 hass，SSH 断开后仍保持运行
#   • 若存在 .disabled 标志文件（由 stop.sh 创建），先删除，使 autocheck 能重新接管
#   • 日志写入 /sdcard/isgbackup/ha/start_<timestamp>.log
#   • 通过 monitor.py 上报 MQTT 状态：starting → running / failed
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
PROOT_DISTRO="${PROOT_DISTRO:-ubuntu}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
STATUS_SH="$SCRIPT_DIR/status.sh"
DISABLE_FLAG="$SCRIPT_DIR/.disabled"
LOG_ROOT="${BACKUP_DIR:-/sdcard/isgbackup/ha}"
mkdir -p "$LOG_ROOT"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_ROOT}/start_${DATE_TAG}.log"
HASS_RUNTIME_LOG="${LOG_ROOT}/hass_runtime.log"

exec > >(tee -a "$LOG_FILE") 2>&1

printf "======== %s Home Assistant 启动脚本 ========\n" "$(date '+%F %T')"
echo "[INFO] 日志文件: $LOG_FILE"

mqtt_report() { python3 "$MONITOR_PY" --service "$SERVICE_ID" --status "$1" --extra "$2"; }

in_proot() { proot-distro exec "$PROOT_DISTRO" -- bash -c "$*"; }

# ------------------------------------------------------------
# 0. 移除 .disabled 标志（如果存在）
if [[ -f "$DISABLE_FLAG" ]]; then
    rm -f "$DISABLE_FLAG"
    echo "[INFO] 移除 disable flag: $DISABLE_FLAG"
fi

# ------------------------------------------------------------
# 1. 发布 starting 状态
mqtt_report starting "{}"

# ------------------------------------------------------------
# 2. 后台启动 hass (nohup 保留)
START_CMD='source /root/homeassistant/bin/activate && nohup hass >> "${HASS_RUNTIME_LOG}" 2>&1 &'

echo "[INFO] 容器内执行启动命令"
if in_proot "$START_CMD"; then
    echo "[INFO] hass 已后台启动，运行日志: $HASS_RUNTIME_LOG"
else
    echo "[ERROR] hass 启动命令执行失败"
    mqtt_report failed "{\"error\":\"start_cmd_failed\",\"log\":\"$LOG_FILE\"}"
    exit 1
fi

# ------------------------------------------------------------
# 3. 轮询 status.sh 确认运行
MAX_TRIES=30  # 5 分钟
INTERVAL=10
COUNT=0
while (( COUNT < MAX_TRIES )); do
    if "$STATUS_SH" --quiet; then
        echo "[OK] Home Assistant 正常运行"
        mqtt_report running "{\"log\":\"$LOG_FILE\"}"
        echo "======== 启动完成 ========"
        exit 0
    fi
    COUNT=$((COUNT+1)); sleep "$INTERVAL"
done

echo "[ERROR] 启动后超过 ${MAX_TRIES} 次检查仍未运行"
mqtt_report failed "{\"error\":\"runtime_not_up\",\"log\":\"$LOG_FILE\"}"
exit 1
