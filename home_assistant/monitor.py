#!/usr/bin/env python3
"""
Generic MQTT monitor helper
---------------------------
- Publishes status payloads for service scripts (install.sh, backup.sh, etc.)
- Optionally subscribes & prints a topic (diagnostic)

Design principles
* **Single responsibility**: 只处理 MQTT 连接、发布、订阅，不做业务逻辑判断
* **Environment‑driven**: broker 地址、端口、凭证均可通过环境变量覆盖
* **CLI‑friendly**: 通过命令行参数决定 publish / subscribe 动作

Usage examples
--------------
Publish:
    python3 monitor.py --service home_assistant --status running --extra '{"duration":12}'

Subscribe (print retained payload then exit):
    python3 monitor.py --subscribe isg/status/home_assistant
"""
import json, os, sys, time, argparse
from typing import Optional

try:
    import paho.mqtt.client as mqtt  # type: ignore
except ImportError:
    print("[monitor.py] paho-mqtt not installed", file=sys.stderr)
    sys.exit(1)

# ---------------- MQTT connection params ----------------
BROKER_HOST = os.getenv("MQTT_HOST", "127.0.0.1")
BROKER_PORT = int(os.getenv("MQTT_PORT", "1883"))
BROKER_USER = os.getenv("MQTT_USER", "admin")
BROKER_PASS = os.getenv("MQTT_PASS", "admin")
KEEPALIVE   = int(os.getenv("MQTT_KEEPALIVE", "5"))
CLIENT_ID   = os.getenv("MQTT_CLIENT_ID", f"svc-monitor-{int(time.time())}")

# ---------------- CLI ----------------
parser = argparse.ArgumentParser(description="MQTT monitor helper (publish / subscribe)")
parser.add_argument("--service", help="service_id (for publish mode)")
parser.add_argument("--status",  help="status string (publish mode)")
parser.add_argument("--extra",   help="extra JSON (publish mode)")
parser.add_argument("--topic",   help="explicit publish topic (override default)")
parser.add_argument("--subscribe", metavar="TOPIC", help="subscribe a topic and output retained payload then exit")
parser.add_argument("--retain", action="store_true", help="flag: retain message when publishing (default true)")
parser.add_argument("--qos", type=int, default=0, choices=[0,1,2], help="mqtt qos level (default 0)")
args = parser.parse_args()

# ---------------- Connect helper ----------------

def connect_mqtt() -> mqtt.Client:
    client = mqtt.Client(CLIENT_ID)
    if BROKER_USER or BROKER_PASS:
        client.username_pw_set(BROKER_USER, BROKER_PASS)
    client.connect(BROKER_HOST, BROKER_PORT, KEEPALIVE)
    return client

# ---------------- Subscribe mode ----------------
if args.subscribe:
    topic = args.subscribe
    payload_holder: dict[str, Optional[str]] = {"msg": None}

    def on_message(_cli, _ud, msg):
        payload_holder["msg"] = msg.payload.decode() if msg.payload else ""
        print(payload_holder["msg"])
        _cli.disconnect()

    cli = connect_mqtt()
    cli.on_message = on_message
    cli.subscribe(topic, qos=args.qos)
    cli.loop_start()
    # wait max 3 seconds for retained
    time.sleep(3)
    cli.loop_stop()
    sys.exit(0)

# ---------------- Publish mode ----------------
if not (args.service and args.status):
    parser.error("--service and --status are required for publish mode (unless --subscribe)")

try:
    extra_data = json.loads(args.extra) if args.extra else {}
except json.JSONDecodeError as e:
    print(f"[monitor.py] extra JSON decode error: {e}", file=sys.stderr)
    sys.exit(1)

payload = {
    "service": args.service,
    "status": args.status,
    "timestamp": int(time.time())
}
payload.update(extra_data)

publish_topic = args.topic or f"isg/status/{args.service}"

cli = connect_mqtt()
cli.publish(publish_topic, json.dumps(payload), qos=args.qos, retain=True)
cli.disconnect()
