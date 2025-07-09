#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 状态检测脚本（通过 monitor.py 检查 MQTT）
# ------------------------------------------------------------
set -euo pipefail

PORT=${PORT:-8123}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}"}" && pwd)"
MONITOR_PY="$SCRIPT_DIR/monitor.py"

status="stopped"; code=1; pid="null"

# 1) 进程检查
if pid=$(pgrep -f "[h]omeassistant" | head -n1); then
  # 2) 端口检查
  if nc -z -w2 127.0.0.1 "$PORT" 2>/dev/null; then
    # 3) MQTT online 检查（调用 monitor.py）
    mqtt_status=$(python3 "$MONITOR_PY" --service home_assistant --check-online || echo "")
    if [[ "$mqtt_status" == "online" ]]; then
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
