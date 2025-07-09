#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 运行状态检查脚本（进程 + 端口 + MQTT Online）
# 保存路径：/data/data/com.termux/files/home/services/home_assistant/status.sh
# ------------------------------------------------------------
# 检测逻辑：
#   1) 进程是否存在（pgrep）
#   2) 8123 端口是否可连接（127.0.0.1）
#   3) MQTT 保留消息 `homeassistant/status` 是否为 "online"
#
# 输出 / 退出码：
#   running  → exit 0   # 全部 OK
#   starting → exit 2   # 进程 OK，但端口或 MQTT 未就绪
#   stopped  → exit 1   # 未安装或进程不存在
#
# 选项：
#   --json   输出 JSON
#   --quiet  静默，只返回退出码
# ------------------------------------------------------------
set -euo pipefail

SERVICE_ID="home_assistant"
PORT=8123

# MQTT 连接参数（可通过环境变量覆盖）
MQTT_HOST="${MQTT_HOST:-127.0.0.1}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USER:-admin}"
MQTT_PASS="${MQTT_PASS:-admin}"
MQTT_TOPIC="homeassistant/status"
MQTT_TIMEOUT=3   # 秒

VERSION_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/VERSION"

status="stopped"
code=1
pid="null"

# 1) 是否安装（存在 VERSION 文件即可视作已安装脚本）
if [[ ! -f "$VERSION_FILE" ]]; then
    status="stopped"; code=1
else
    # 2) 检查进程（匹配 hass 或 homeassistant）
    if pid=$(pgrep -f "[h]omeassistant" | head -n1); then
        # 3) 检查端口
        if nc -z -w2 127.0.0.1 "$PORT" 2>/dev/null; then
            # 4) 检查 MQTT online
            online=$(python3 - <<PY 2>/dev/null || echo "error")
import paho.mqtt.client as m, time, sys
msg="error"

def on_message(cli,userdata,ms):
    global msg
    msg=ms.payload.decode() if ms.payload else ""
    cli.disconnect()

try:
    cli=m.Client()
    cli.username_pw_set("${MQTT_USER}", "${MQTT_PASS}")
    cli.on_message=on_message
    cli.connect("${MQTT_HOST}", ${MQTT_PORT}, ${MQTT_TIMEOUT})
    cli.subscribe("${MQTT_TOPIC}")
    cli.loop_start()
    time.sleep(${MQTT_TIMEOUT})
    cli.loop_stop()
except Exception:
    pass
print(msg)
PY)
            if [[ "$online" == "online" ]]; then
                status="running"; code=0
            else
                status="starting"; code=2
            fi
        else
            status="starting"; code=2
        fi
    else
        status="stopped"; code=1
    fi
fi

# ---------- 输出 ----------
if [[ "${1:-}" == "--quiet" ]]; then
    exit $code
fi

if [[ "${1:-}" == "--json" ]]; then
    printf '{"status":"%s","pid":%s}\n' "$status" "${pid}"
else
    echo "$status"
fi

exit $code
