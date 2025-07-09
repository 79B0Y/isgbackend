#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 升级脚本
# 路径：/data/data/com.termux/files/home/services/home_assistant/update.sh
# 职责：
#   • 将虚拟环境中的 Home Assistant 升级/降级到指定版本
#   • 版本号来源：环境变量 TARGET_VERSION 或脚本第一个参数
#   • 仅执行版本切换，脚本自身不会在线更新
#   • 过程写入日志 /sdcard/isgbackup/ha/update_<timestamp>.log
#   • MQTT 上报：updating → update_success / update_failed
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
PROOT_DISTRO="${PROOT_DISTRO:-ubuntu}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
START_SH="$SCRIPT_DIR/start.sh"
STOP_SH="$SCRIPT_DIR/stop.sh"
LOG_ROOT="${BACKUP_DIR:-/sdcard/isgbackup/ha}"
mkdir -p "$LOG_ROOT"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_ROOT}/update_${DATE_TAG}.log"

exec > >(tee -a "$LOG_FILE") 2>&1

printf "======== %s Home Assistant 升级脚本 ========\n" "$(date '+%F %T')"

echo "[INFO] 日志文件: $LOG_FILE"

mqtt_report() {
    python3 "$MONITOR_PY" --service "$SERVICE_ID" --status "$1" --extra "$2"
}

in_proot() { proot-distro exec "$PROOT_DISTRO" -- bash -c "$*"; }

# ------------------------------------------------------------
# 0. 获取目标版本
TARGET_VERSION="${TARGET_VERSION:-${1:-}}"
if [[ -z "$TARGET_VERSION" ]]; then
    echo "用法: TARGET_VERSION=<version> bash update.sh  或  bash update.sh <version>"
    exit 1
fi

echo "[INFO] 目标版本: $TARGET_VERSION"

# ------------------------------------------------------------
# 1. 上报 updating
mqtt_report updating "{\"target\":\"$TARGET_VERSION\"}"

# ------------------------------------------------------------
# 2. 停止当前服务
bash "$STOP_SH" || true

# ------------------------------------------------------------
# 3. 升级/降级 pip 包
UPGRADE_CMD="source /root/homeassistant/bin/activate && pip install --upgrade --no-cache-dir homeassistant==${TARGET_VERSION}"

echo "[INFO] 容器内执行: $UPGRADE_CMD"
if in_proot "$UPGRADE_CMD"; then
    echo "[OK] pip 安装完成"
else
    echo "[ERROR] pip 安装失败"
    mqtt_report update_failed "{\"error\":\"pip_failed\",\"log\":\"$LOG_FILE\"}"
    exit 1
fi

# ------------------------------------------------------------
# 4. 重启服务
bash "$START_SH"

# ------------------------------------------------------------
# 5. 成功上报
mqtt_report update_success "{\"version\":\"$TARGET_VERSION\",\"log\":\"$LOG_FILE\"}"

echo "======== 升级到 $TARGET_VERSION 完成 ========"

