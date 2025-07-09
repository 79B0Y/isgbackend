#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 自检 & 自愈脚本
# 路径：/data/data/com.termux/files/home/services/home_assistant/autocheck.sh
# 功能：
#   • 健康检查 → 安装 / 还原 / 启动 / 版本更新
#   • 若存在 .disabled 则只上报 disabled
#   • 防并发 flock 锁；失败计数阈值可配置
#   • 更新检查周期可通过环境变量调整
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
PROOT_DISTRO="${PROOT_DISTRO:-ubuntu}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
STATUS_SH="$SCRIPT_DIR/status.sh"
START_SH="$SCRIPT_DIR/start.sh"
INSTALL_SH="$SCRIPT_DIR/install.sh"
RESTORE_SH="$SCRIPT_DIR/restore.sh"
UPDATE_SH="$SCRIPT_DIR/update.sh"
DISABLE_FLAG="$SCRIPT_DIR/.disabled"
FAIL_CNT_FILE="$SCRIPT_DIR/fail.count"
LOCK_FILE="/var/lock/ha_autocheck.lock"
LAST_UPDATE_TAG="$SCRIPT_DIR/.last_update_check"

# ---------------- 可配置环境变量 ----------------
AC_MAX_FAILS="${AC_MAX_FAILS:-3}"            # 连续失败 N 次后 permanent_failed
AC_UPDATE_INTERVAL="${AC_UPDATE_INTERVAL:-21600}"  # 版本检查间隔（秒），默认 6h
BACKUP_DIR="${BACKUP_DIR:-/sdcard/isgbackup/ha}"

# 首次加载配置后立即上报当前参数
mqtt_report config "{\"max_fails\":${AC_MAX_FAILS},\"update_interval\":${AC_UPDATE_INTERVAL}}"

# ---------------- 日志设置 ----------------
mkdir -p "$BACKUP_DIR"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${BACKUP_DIR}/autocheck_${DATE_TAG}.log"
exec >> "$LOG_FILE" 2>&1

# ---------------- 辅助函数 ----------------
mqtt_report() { python3 "$MONITOR_PY" --service "$SERVICE_ID" --status "$1" --extra "$2"; }
in_proot()    { proot-distro exec "$PROOT_DISTRO" -- bash -c "$*"; }
log()         { printf '[%s] %s\n' "$(date '+%F %T')" "$1"; }

# ------------------------------------------------------------
# 0. 防并发锁
exec 200>"$LOCK_FILE" || exit 1
if ! flock -n 200; then log "已有实例运行，退出"; exit 0; fi

# ------------------------------------------------------------
# 1. disabled 标志
if [[ -f "$DISABLE_FLAG" ]]; then
    log "发现 .disabled，跳过自愈"
    mqtt_report disabled "{}"
    exit 0
fi

# ------------------------------------------------------------
# 2. 安装检查
if [[ ! -f "$SCRIPT_DIR/VERSION" ]]; then
    log "未安装（缺少 VERSION），执行 install.sh"
    bash "$INSTALL_SH"
fi

# ------------------------------------------------------------
# 3. 配置目录检查
if ! in_proot '[ -d /root/.homeassistant ]'; then
    log "配置目录缺失，执行 restore.sh"
    bash "$RESTORE_SH" || true
fi

# ------------------------------------------------------------
# 4. 运行状态 & 自愈
if "$STATUS_SH" --quiet; then
    log "状态 running"
    mqtt_report running "{\"log\":\"$LOG_FILE\"}"
else
    log "非运行状态，执行 start.sh"
    bash "$START_SH" || true
    sleep 5
    if "$STATUS_SH" --quiet; then
        log "启动后恢复成功"
        rm -f "$FAIL_CNT_FILE" || true
        mqtt_report recovered "{\"log\":\"$LOG_FILE\"}"
    else
        cnt=$(cat "$FAIL_CNT_FILE" 2>/dev/null || echo 0)
        cnt=$((cnt+1))
        echo "$cnt" > "$FAIL_CNT_FILE"
        log "启动失败，累计 $cnt 次"
        if (( cnt >= AC_MAX_FAILS )); then
            mqtt_report permanent_failed "{\"fail_count\":$cnt,\"log\":\"$LOG_FILE\"}"
        else
            mqtt_report failed "{\"fail_count\":$cnt,\"log\":\"$LOG_FILE\"}"
        fi
        exit 1
    fi
fi

# ------------------------------------------------------------
# 5. 版本更新检查
if [[ -n "${TARGET_VERSION:-}" ]]; then
    need_check=false
    if [[ ! -f "$LAST_UPDATE_TAG" ]]; then
        need_check=true
    else
        last=$(cat "$LAST_UPDATE_TAG")
        if (( $(date +%s) - last >= AC_UPDATE_INTERVAL )); then need_check=true; fi
    fi
    if $need_check; then
        date +%s > "$LAST_UPDATE_TAG"
        log "触发 update.sh → $TARGET_VERSION"
        bash "$UPDATE_SH" "$TARGET_VERSION" || true
    fi
fi

log "自检完成"
exit 0

