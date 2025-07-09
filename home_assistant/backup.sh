
#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 配置目录备份脚本
# 放置于 /opt/services/home_assistant/backup.sh
# 依赖：busybox/gnu tar、python3、monitor.py（同目录）
# 运行状态检测：调用 status.sh，仅当输出 running 时才开始备份。
# 压缩打包：将 /root/.homeassistant 打成 homeassistant_backup_日期.tar.gz，默认保存到 /sdcard/isgbackup/ha。
# MQTT 上报：所有状态（running / success / skipped / failed）统一通过同目录 monitor.py 发送。
# 旧备份清理：默认保留最新 3 份，数量可用环境变量 KEEP_BACKUPS 覆盖。
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
STATUS_SH="$SCRIPT_DIR/status.sh"

# —— 可通过环境变量覆盖 ——
HA_DIR="${HA_DIR:-/root/.homeassistant}"
BACKUP_DIR="${BACKUP_DIR:-/sdcard/isgbackup/ha}"
KEEP_BACKUPS="${KEEP_BACKUPS:-3}"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/homeassistant_backup_${DATE_TAG}.tar.gz"

mkdir -p "$BACKUP_DIR"

# ------------------------------------------------------------
# MQTT 上报封装
# 参数：$1 = status 值 (running|success|skipped|failed)
# 参数：$2 = 附加 JSON（可为空）
# ------------------------------------------------------------
function mqtt_report() {
    local status="$1"; shift || true
    local extra_json="$1"
    python3 "$MONITOR_PY" --status "${status}" --extra "${extra_json}"
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
# 2. 执行打包备份
# ------------------------------------------------------------
start_ts=$(date +%s)

echo "[INFO] 打包目录: $HA_DIR -> $BACKUP_FILE"
if tar -czf "$BACKUP_FILE" -C "$HA_DIR" . ; then
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
# 3. 清理旧备份，仅保留最新 N 份
# ------------------------------------------------------------
mapfile -t old_files < <(ls -1t "$BACKUP_DIR"/homeassistant_backup_*.tar.gz 2>/dev/null | tail -n +$((KEEP_BACKUPS+1)))
for f in "${old_files[@]:-}"; do
    echo "[INFO] 删除旧备份: $f"
    rm -f "$f" || true
done
