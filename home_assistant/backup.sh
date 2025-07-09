#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 配置目录备份脚本
# 存放路径：/data/data/com.termux/files/home/services/home_assistant/backup.sh
# 运行环境：脚本位于 **Termux 宿主**，Home Assistant 数据位于 **proot-distro 容器 (ubuntu)**。
# 主要功能：
#   1. 调用 status.sh 检测服务是否运行
#   2. 通过抽象函数 in_proot() 在容器内执行 tar 打包
#   3. 生成备份文件并通过 monitor.py 统一 MQTT 上报
#   4. 自动清理旧备份（默认保留 3 份，可通过 KEEP_BACKUPS 覆盖）
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
STATUS_SH="$SCRIPT_DIR/status.sh"

# ——— 环境变量可覆盖 ———
HA_DIR="${HA_DIR:-/root/.homeassistant}"
BACKUP_DIR="${BACKUP_DIR:-/sdcard/isgbackup/ha}"
KEEP_BACKUPS="${KEEP_BACKUPS:-3}"
PROOT_DISTRO="${PROOT_DISTRO:-ubuntu}"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/homeassistant_backup_${DATE_TAG}.tar.gz"

mkdir -p "$BACKUP_DIR"

# ------------------------------------------------------------
# 抽象函数：in_proot()
# ------------------------------------------------------------
# 功能：在指定的 proot-distro 容器内部执行命令。
#   - 默认容器名由环境变量 PROOT_DISTRO 决定（缺省为 ubuntu）。
#   - 用法示例：in_proot ls -l /root
#   - 如需传递环境变量，可在调用前 export，然后再 in_proot <cmd>。
# ------------------------------------------------------------
function in_proot() {
    proot-distro exec "$PROOT_DISTRO" -- "$@"
}

# ------------------------------------------------------------
# MQTT 上报封装
# 参数：$1 = status (running|success|skipped|failed)
# 参数：$2 = 附加 JSON（可为空）
# ------------------------------------------------------------
function mqtt_report() {
    local status="$1"; shift || true
    local extra_json="${1:-}"
    python3 "$MONITOR_PY" --status "$status" --extra "$extra_json"
}

# ------------------------------------------------------------
# 1. 检查服务运行状态
# ------------------------------------------------------------
if "$STATUS_SH" | grep -q "^running"; then
    echo "[INFO] $SERVICE_ID 正在运行，开始备份…"
    mqtt_report running "{}"
else
    echo "[WARN] $SERVICE_ID 未运行，跳过备份。"
    mqtt_report skipped "{\"reason\":\"service_not_running\"}"
    exit 0
fi

# ------------------------------------------------------------
# 2. 执行打包备份（容器内 tar）
# ------------------------------------------------------------
start_ts=$(date +%s)

echo "[INFO] in_proot tar -czf $BACKUP_FILE -C $HA_DIR ."
if in_proot tar -czf "$BACKUP_FILE" -C "$HA_DIR" . ; then
    dur=$(( $(date +%s) - start_ts ))
    size_kb=$(du -sk "$BACKUP_FILE" | awk '{print $1}')
    echo "[INFO] 备份完成 (${size_kb} KB, ${dur}s)"
    mqtt_report success "{\"file\":\"${BACKUP_FILE}\",\"size_kb\":${size_kb},\"duration\":${dur}}"
else
    echo "[ERROR] tar 失败，备份未完成"
    mqtt_report failed "{\"error\":\"tar_failed\"}"
    exit 1
fi

# ------------------------------------------------------------
# 3. 清理旧备份
# ------------------------------------------------------------
mapfile -t old_files < <(ls -1t "$BACKUP_DIR"/homeassistant_backup_*.tar.gz 2>/dev/null | tail -n +$((KEEP_BACKUPS+1)))
for f in "${old_files[@]:-}"; do
    echo "[INFO] 删除旧备份: $f"
    rm -f "$f" || true
done
