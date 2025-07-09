#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 状态检测脚本（修复 here-doc 终止行）
# ------------------------------------------------------------
set -euo pipefail

PORT=${PORT:-8123}
MQTT_HOST="${MQTT_HOST:-127.0.0.1}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_USER="${MQTT_USER:-admin}"
MQTT_PASS="${MQTT_PASS:-admin}"
MQTT_TOPIC="${MQTT_TOPIC:-homeassistant/status}"
MQTT_TIMEOUT=${MQTT_TIMEOUT:-3}

status="stopped"; code=1; pid="null"

# 1) 进程
if pid=$(pgrep -f "[h]omeassistant" | head -n1); then
  # 2) 端口
  if nc -z -w2 127.0.0.1 "$PORT" 2>/dev/null; then
    # 3) MQTT online
    online=$(python3 - <<'PY'
import os, time
import paho.mqtt.client as m
res = ""

def cb(cli, ud, msg):
    global res
    res = msg.payload.decode() if msg.payload else ""
    cli.disconnect()

cli = m.Client()
cli.username_pw_set(os.getenv("MQTT_USER"), os.getenv("MQTT_PASS"))
cli.on_message = cb
try:
    cli.connect(os.getenv("MQTT_HOST"), int(os.getenv("MQTT_PORT")), int(os.getenv("MQTT_TIMEOUT", "3")))
    cli.subscribe(os.getenv("MQTT_TOPIC"))
    cli.loop_start()
    time.sleep(int(os.getenv("MQTT_TIMEOUT", "3")))
    cli.loop_stop()
except Exception:
    pass
print(res)
PY
)
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

case "${1:-}" in
  --json) printf '{"status":"%s","pid":%s}\n' "$status" "$pid";;
  --quiet) ;;
  *) echo "$status";;
esac

exit $code
