#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 运行状态检查脚本（进程 + 端口 + MQTT Online）
# 保存路径：/opt/services/home_assistant/status.sh
#
# 逻辑说明：
#   1) 进程存活判定（PID / pgrep）
#   2) 8123 端口可连接
#   3) MQTT Topic `homeassistant/status` == online
#      → 第 3 步通过同目录的 monitor.py 来完成订阅检测，保持 MQTT 交互统一入口
#
# 返回值：
#   0 = running   （三项全部 OK）
#   2 = starting  （仅进程 OK）
#   1 = stopped   （进程不存在）
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"
PID_FILE="/var/run/${SERVICE_ID}.pid"
PROCESS_KEY="homeassistant"       # 根据实际启动命令调整

# ---------- 端口检测 ----------
HA_PORT="${HA_PORT:-8123}"
PORT_TIMEOUT="${PORT_TIMEOUT:-5}"

# ---------- MQTT 检测 ----------
MQTT_TOPIC="${MQTT_TOPIC:-homeassistant/status}"
MQTT_TIMEOUT="${MQTT_TIMEOUT:-60}"

state_pid=false
state_port=false
state_mqtt=false
pid=""

# --- 1. 进程检测 ---
if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if [[ -n "$pid" ]] && ps -p "$pid" -o cmd= 2>/dev/null | grep -q "$PROCESS_KEY"; then
        state_pid=true
    fi
fi

if [[ "$state_pid" == false ]] && pgrep -f "$PROCESS_KEY" >/dev/null 2>&1; then
    pid=$(pgrep -f -o "$PROCESS_KEY")
    state_pid=true
fi

# 若进程不存在，直接 stopped
if [[ "$state_pid" == false ]]; then
    echo "stopped"
    exit 1
fi

# --- 2. 端口检测 ---
if timeout "$PORT_TIMEOUT" bash -c "</dev/tcp/127.0.0.1/$HA_PORT" >/dev/null 2>&1; then
    state_port=true
fi

# --- 3. MQTT online 检测（统一调用 monitor.py） ---
if python3 "$MONITOR_PY" --check_topic_online "$MQTT_TOPIC" --timeout "$MQTT_TIMEOUT"; then
    state_mqtt=true
fi

# --- 4. 输出 ---
if [[ "$state_port" == true && "$state_mqtt" == true ]]; then
    echo "running (pid=$pid,port=$HA_PORT,mqtt=online)"
    exit 0
else
    echo "starting (pid=$pid,port_ok=$state_port,mqtt_online=$state_mqtt)"
    exit 2
fi

