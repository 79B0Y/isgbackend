#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 还原脚本
# 路径：/data/data/com.termux/files/home/services/home_assistant/restore.sh
# 功能：
#   1. 从最新备份 homeassistant_backup_*.tar.gz 还原；若无则使用 homeassistant_original.tar.gz
#   2. 停止服务 → 清空 /root/.homeassistant → 解压 → 重新启动服务
#   3. 日志写入 /sdcard/isgbackup/ha/restore_<timestamp>.log
#   4. 上报 MQTT：restoring → restore_success / restore_failed（monitor.py）
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
PROOT_DISTRO="${PROOT_DISTRO:-ubuntu}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
STOP_SH="$SCRIPT_DIR/stop.sh"
START_SH="$SCRIPT_DIR/start.sh"
LOG_ROOT="${BACKUP_DIR:-/sdcard/isgbackup/ha}"
mkdir -p "$LOG_ROOT"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_ROOT}/restore_${DATE_TAG}.log"
BACKUP_DIR="$LOG_ROOT"
DEFAULT_BACKUP="homeassistant_original.tar.gz"

exec > >(tee -a "$LOG_FILE") 2>&1

printf "======== %s Home Assistant 还原脚本 ========\n" "$(date '+%F %T')"
echo "[INFO] 日志文件: $LOG_FILE"

mqtt_report() {
    python3 "$MONITOR_PY" --service "$SERVICE_ID" --status "$1" --extra "$2"
}

in_proot() { proot-distro exec "$PROOT_DISTRO" -- bash -c "$*"; }

# ------------------------------------------------------------
# 0. 选择备份文件
if [[ -n "${1:-}" ]]; then
    CHOSEN="$1"
else
    CHOSEN=$(ls -1t "$BACKUP_DIR"/homeassistant_backup_*.tar.gz 2>/dev/null | head -n1 || true)
fi

if [[ -z "$CHOSEN" ]]; then
    if [[ -f "$BACKUP_DIR/$DEFAULT_BACKUP" ]]; then
        CHOSEN="$BACKUP_DIR/$DEFAULT_BACKUP"
        FROM_DEFAULT=true
    else
        echo "[ERROR] 未找到任何备份文件"
        mqtt_report restore_failed "{\"error\":\"no_backup\",\"log\":\"$LOG_FILE\"}"
        exit 1
    fi
fi

BACKUP_PATH="$CHOSEN"
[[ "$BACKUP_PATH" != /* ]] && BACKUP_PATH="$BACKUP_DIR/$BACKUP_PATH"
echo "[INFO] 选用备份文件: $BACKUP_PATH"

# ------------------------------------------------------------
# 1. 上报 restoring
mqtt_report restoring "{\"file\":\"$BACKUP_PATH\"}"

# ------------------------------------------------------------
# 2. 停止 Home Assistant
bash "$STOP_SH" || true

# ------------------------------------------------------------
# 3. 清空并解压
CLEAR_CMD='rm -rf /root/.homeassistant && mkdir -p /root/.homeassistant'
EXTRACT_CMD="tar -xzf '$BACKUP_PATH' -C /root --strip-components=1 --transform='s|^\.homeassistant/||'"

echo "[INFO] 清空旧配置目录"
in_proot "$CLEAR_CMD"

echo "[INFO] 解压备份到容器 /root"
if in_proot "$EXTRACT_CMD"; then
    echo "[OK] 解压完成"
else
    echo "[ERROR] 解压失败"
    mqtt_report restore_failed "{\"error\":\"tar_failed\",\"log\":\"$LOG_FILE\"}"
    exit 1
fi

# ------------------------------------------------------------
# 4. 重新启动服务
bash "$START_SH"

# ------------------------------------------------------------
# 5. 成功上报
mqtt_report restore_success "{\"file\":\"$BACKUP_PATH\",\"log\":\"$LOG_FILE\"}"

echo "======== 还原完成 ========"

