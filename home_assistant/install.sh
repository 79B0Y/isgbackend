#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 安装脚本（无数字编号）
# 路径：/data/data/com.termux/files/home/services/home_assistant/install.sh
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
PROOT_DISTRO="${PROOT_DISTRO:-ubuntu}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
LOG_ROOT="${BACKUP_DIR:-/sdcard/isgbackup/ha}"
mkdir -p "$LOG_ROOT"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_ROOT}/install_${DATE_TAG}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "======== $(date '+%F %T') Home Assistant 安装开始 ========"

echo "[INFO] 日志文件: $LOG_FILE"

# ------------------------------------------------------------
# 工具函数
# ------------------------------------------------------------
 mqtt_report() { python3 "$MONITOR_PY" --status "$1" --extra "$2"; }
 in_proot()    { proot-distro exec "$PROOT_DISTRO" -- bash -c "$*"; }
 log_step()    { printf '\n[%s] %s\n' "$(date '+%F %T')" "$1"; }
 run_or_fail() {
   local desc="$1"; shift
   local cmd="$*"
   log_step "$desc → $cmd"
   if in_proot "$cmd"; then
       echo "[OK] $desc"
   else
       echo "[ERROR] $desc"
       mqtt_report install_failed "{\"step\":\"$desc\",\"log\":\"$LOG_FILE\"}"
       exit 1
   fi
 }

# ------------------------------------------------------------
# 1. 更新系统并安装依赖
log_step "更新 apt 索引并安装系统依赖 (ffmpeg libturbojpeg)"
run_or_fail "apt update" "apt update -y"
run_or_fail "安装 ffmpeg libturbojpeg" "apt install -y ffmpeg libturbojpeg"

# 2. 创建并初始化 Python 虚拟环境
log_step "创建 Python 虚拟环境 /root/homeassistant"
run_or_fail "创建 venv" "python3 -m venv /root/homeassistant"

log_step "安装 Python 库 (numpy mutagen pillow 等)"
PY_SETUP='source /root/homeassistant/bin/activate && \
  pip install --upgrade pip && \
  pip install numpy mutagen pillow aiohttp_fast_zlib && \
  pip install aiohttp==3.10.8 attrs==23.2.0 && \
  pip install PyTurboJPEG'
run_or_fail "安装基础依赖" "$PY_SETUP"

# 3. 安装 Home Assistant
log_step "安装 Home Assistant 2025.5.3"
run_or_fail "pip 安装 Home Assistant" "source /root/homeassistant/bin/activate && pip install homeassistant==2025.5.3"

# 4. 首启生成配置目录
log_step "首次启动 Home Assistant，生成配置目录"
HASS_PID=$(in_proot "source /root/homeassistant/bin/activate && hass & echo \$!")
echo "[INFO] 初始化进程 PID: $HASS_PID"

MAX_TRIES=90; COUNT=0
while (( COUNT < MAX_TRIES )); do
    if nc -z 127.0.0.1 8123 2>/dev/null; then
        echo "[INFO] Home Assistant Web 已就绪"
        break
    fi
    COUNT=$((COUNT+1)); sleep 60
done
if (( COUNT >= MAX_TRIES )); then
    echo "[ERROR] 初始化超时"
    in_proot "kill $HASS_PID || true"
    mqtt_report install_failed "{\"error\":\"init_timeout\",\"log\":\"$LOG_FILE\"}"
    exit 1
fi

# 5. 终止并优化压缩库
log_step "终止首次启动进程并安装 zlib-ng / isal"
in_proot "kill $HASS_PID"
run_or_fail "安装 zlib-ng isal" "source /root/homeassistant/bin/activate && pip install zlib-ng isal --no-binary :all:"

# 6. 调整 configuration.yaml
log_step "配置 logger 为 critical & 允许 iframe"
in_proot "grep -q '^logger:' /root/.homeassistant/configuration.yaml || echo -e '\nlogger:\n  default: critical' >> /root/.homeassistant/configuration.yaml"
in_proot "grep -q 'use_x_frame_options:' /root/.homeassistant/configuration.yaml || echo -e '\nhttp:\n  use_x_frame_options: false' >> /root/.homeassistant/configuration.yaml"

# 7. 完成并上报
VERSION_STR=$(in_proot "source /root/homeassistant/bin/activate && hass --version")
log_step "安装完成，Home Assistant 版本: $VERSION_STR"

echo "======== Home Assistant 安装脚本结束 ========"

mqtt_report install_success "{\"version\":\"$VERSION_STR\",\"log\":\"$LOG_FILE\"}"

