#!/usr/bin/env python3
"""
Home Assistant 监控 / MQTT 上报脚本
保存路径：/data/data/com.termux/files/home/services/home_assistant/monitor.py

用法示例：
    python3 monitor.py --status running --pid 22104
    python3 monitor.py --status backup_success --extra '{"file":"/sdcard/...tar.gz"}'

脚本特性：
- 读取环境变量以获取 MQTT 参数；全部有默认值，方便离线测试。
- `--service` 可覆盖服务 ID，默认 `home_assistant`（因此本脚本也可被其他服务复用）。
- `--status` 必填；`--pid` 与 `--extra` 选填。
- 以 QoS 1 + retain 发布到 `isg/status/<service>`。
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

try:
    import paho.mqtt.client as mqtt
except ImportError:
    print("[ERROR] 未安装 paho-mqtt，请先执行: pip install paho-mqtt", file=sys.stderr)
    sys.exit(1)

# ------------------------ 环境变量 ------------------------
MQTT_HOST = os.environ.get("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.environ.get("MQTT_PORT", 1883))
MQTT_USER = os.environ.get("MQTT_USER", "admin")
MQTT_PASS = os.environ.get("MQTT_PASS", "admin")
MQTT_QOS = int(os.environ.get("MQTT_QOS", 1))
TOPIC_PREFIX = os.environ.get("TOPIC_PREFIX", "isg/status")

# ------------------------ CLI 解析 ------------------------
parser = argparse.ArgumentParser(description="Publish Home Assistant runtime status via MQTT")
parser.add_argument("--service", default="home_assistant", help="service_id，默认 home_assistant")
parser.add_argument("--status", required=True, help="状态码，例如 running / stopped / backup_success 等")
parser.add_argument("--pid", type=int, help="进程 PID，可选")
parser.add_argument("--extra", help="额外 JSON 字符串，可选")
args = parser.parse_args()

# ------------------------ 组装 Payload -------------------
payload = {
    "service": args.service,
    "status": args.status,
    "timestamp": int(time.time())
}

# 读取脚本版本（同目录 VERSION 文件）
version_file = Path(__file__).resolve().parent / "VERSION"
if version_file.exists():
    payload["script_version"] = version_file.read_text().strip()

if args.pid:
    payload["pid"] = args.pid

if args.extra:
    try:
        extra_dict = json.loads(args.extra)
        payload.update(extra_dict)
    except json.JSONDecodeError:
        payload["extra_raw"] = args.extra  # 解析失败时以原字符串附加

# ------------------------ MQTT 发布 ----------------------
client = mqtt.Client(client_id=f"monitor-{args.service}-{os.getpid()}")
client.username_pw_set(MQTT_USER, MQTT_PASS)
try:
    client.connect(MQTT_HOST, MQTT_PORT, 10)
except Exception as e:
    print(f"[ERROR] 无法连接 MQTT Broker: {e}", file=sys.stderr)
    sys.exit(1)

topic = f"{TOPIC_PREFIX}/{args.service}"
client.publish(topic, json.dumps(payload, ensure_ascii=False), qos=MQTT_QOS, retain=True)
client.disconnect()

print(f"[INFO] Published to {topic}: {payload}")
