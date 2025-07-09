#!/usr/bin/env bash
# ------------------------------------------------------------
# Home Assistant 状态检测脚本（不再使用 MQTT，避免非保留消息误判）
# ------------------------------------------------------------
set -euo pipefail

PORT=${PORT:-8123}

log() {
  echo "[status] $1" >&2
}

status="stopped"; code=1; pid="null"
log "开始状态检查..."

# 1) 进程检查
if pid=$(pgrep -f "[h]omeassistant" | head -n1); then
  log "发现进程 PID: $pid"

  # 2) 端口检查
  if curl -s --head --request GET "http://127.0.0.1:$PORT" | grep -qE "200 OK|302 Found"; then
    status="running"; code=0
    log "状态: running ✅（进程存在，端口 $PORT 可访问）"
  else
    status="starting"; code=2
    log "状态: starting（端口 $PORT 不可达）⚠️"
  fi
else
  status="stopped"; code=1
  log "状态: stopped（未检测到 Home Assistant 进程）❌"
fi

case "${1:-}" in
  --json) printf '{"status":"%s","pid":%s}\n' "$status" "$pid";;
  --quiet) ;;
  *) echo "$status";;
esac

exit $code
