#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 卸载脚本
# 路径：/data/data/com.termux/files/home/services/home_assistant/uninstall.sh
# 职责：
#   1. 调用 stop.sh 终止所有 hass 进程
#   2. 删除虚拟环境 /root/homeassistant 及配置目录 /root/.homeassistant
#   3. 写 uninstall_<timestamp>.log 到 /sdcard/isgbackup/ha/
#   4. 创建 .disabled 标志，阻止 autocheck.sh 误重装/重启
#   5. MQTT 上报 uninstall_success / uninstall_failed
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
PROOT_DISTRO="${PROOT_DISTRO:-ubuntu}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
STOP_SH="$SCRIPT_DIR/stop.sh"
DISABLE_FLAG="$SCRIPT_DIR/.disabled"
LOG_ROOT="${BACKUP_DIR:-/sdcard/isgbackup/ha}"
mkdir -p "$LOG_ROOT"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_ROOT}/uninstall_${DATE_TAG}.log"

exec > >(tee -a "$LOG_FILE") 2>&1

printf "======== %s Home Assistant 卸载脚本 ========\n" "$(date '+%F %T')"

mqtt_report() { python3 "$MONITOR_PY" --service "$SERVICE_ID" --status "$1" --extra "$2"; }

in_proot() { proot-distro exec "$PROOT_DISTRO" -- bash -c "$*"; }

# ------------------------------------------------------------
# 1. 停止服务
if bash "$STOP_SH"; then
    echo "[INFO] Home Assistant 已停止"
else
    echo "[WARN] stop.sh 返回非 0，尝试继续卸载"
fi

# ------------------------------------------------------------
# 2. 删除文件与目录
REMOVE_CMDS='rm -rf /root/homeassistant /root/.homeassistant'

echo "[INFO] 容器内执行: $REMOVE_CMDS"
if in_proot "$REMOVE_CMDS"; then
    echo "[INFO] 目录删除完成"
else
    echo "[ERROR] 目录删除失败"
    mqtt_report uninstall_failed "{\"error\":\"rm_failed\",\"log\":\"$LOG_FILE\"}"
    exit 1
fi

# ------------------------------------------------------------
# 3. 创建 disable 标志文件
if [[ ! -f "$DISABLE_FLAG" ]]; then
    touch "$DISABLE_FLAG"
    echo "[INFO] 已创建 disable flag: $DISABLE_FLAG"
fi

# ------------------------------------------------------------
# 4. 完成上报
mqtt_report uninstall_success "{\"log\":\"$LOG_FILE\"}"

echo "======== 卸载完成 ========"

