
#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 停止脚本
# 路径：/data/data/com.termux/files/home/services/home_assistant/stop.sh
# 功能：
#   • 在 proot-distro 容器内彻底杀掉 hass 进程
#   • 写入日志 /sdcard/isgbackup/ha/stop_<timestamp>.log
#   • 创建标志文件 .disabled ，供 autocheck.sh 检测后不再重启
#   • MQTT 上报 status=stopped  (使用 monitor.py)
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
PROOT_DISTRO="${PROOT_DISTRO:-ubuntu}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
DISABLE_FLAG="$SCRIPT_DIR/.disabled"   # autocheck.sh 遇到此文件即跳过启动
STATUS_SH="$SCRIPT_DIR/status.sh"
LOG_ROOT="${BACKUP_DIR:-/sdcard/isgbackup/ha}"
mkdir -p "$LOG_ROOT"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_ROOT}/stop_${DATE_TAG}.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "======== $(date '+%F %T') Home Assistant 停止脚本 ========"

echo "[INFO] 日志文件: $LOG_FILE"

mqtt_report() {
    python3 "$MONITOR_PY" --service "$SERVICE_ID" --status "$1" --extra "$2"
}

in_proot() { proot-distro exec "$PROOT_DISTRO" -- bash -c "$*"; }

# ------------------------------------------------------------
# 1. 标记手动停止
# ------------------------------------------------------------
if [[ ! -f "$DISABLE_FLAG" ]]; then
    touch "$DISABLE_FLAG"
    echo "[INFO] 创建 disable flag: $DISABLE_FLAG"
fi

# ------------------------------------------------------------
# 2. 杀掉 hass 进程
# ------------------------------------------------------------
KILL_CMD='pkill -f "[h]ass" || pkill -f "[h]omeassistant" || true'

echo "[INFO] 容器内执行: $KILL_CMD"
in_proot "$KILL_CMD"

# 再尝试等待退出
sleep 3

# ------------------------------------------------------------
# 3. 验证停止成功
# ------------------------------------------------------------
if "$STATUS_SH" --quiet; then
    echo "[WARN] 进程仍在运行，强制 kill -9"
    in_proot 'pkill -9 -f "[h]ass" || pkill -9 -f "[h]omeassistant" || true'
    sleep 2
fi

if "$STATUS_SH" --quiet; then
    echo "[ERROR] 仍检测到运行进程，停止失败"
    mqtt_report failed "{\"error\":\"kill_failed\",\"log\":\"$LOG_FILE\"}"
    exit 1
fi

echo "[OK] Home Assistant 已停止"
mqtt_report stopped "{\"log\":\"$LOG_FILE\"}"

echo "======== 停止完成 ========"
