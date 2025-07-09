#!/usr/bin/env python3
"""
monitor.py
===========
统一的 MQTT 上报道具 + Topic 状态检测工具
调用方式：
 1) 上报状态
    python3 monitor.py --status running --extra '{"pid":123}'

 2) 等待指定 Topic 收到 "online" 字符串（status.sh 调用）
    python3 monitor.py --check_topic_online homeassistant/status --timeout 60
"""
import argparse
import json
import sys
import time

from paho.mqtt import client as mqtt_client

# 默认 MQTT 参数，可被环境变量覆盖
import os
MQTT_HOST = os.getenv("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USER = os.getenv("MQTT_USER", "admin")
MQTT_PASS = os.getenv("MQTT_PASS", "admin")
TOPIC_PREFIX = os.getenv("MQTT_TOPIC_PREFIX", "isg/status")

parser = argparse.ArgumentParser()
parser.add_argument("--status", help="status tag to publish (running/stopped/etc)")
parser.add_argument("--pid", type=int, help="process id")
parser.add_argument("--extra", help="extra JSON payload")
parser.add_argument("--service", default="home_assistant", help="service id")

# 用于 status.sh 调用的在线检测
parser.add_argument("--check_topic_online", help="topic to wait for 'online' payload")
parser.add_argument("--timeout", type=int, default=60, help="wait seconds")

args = parser.parse_args()

# --- MQTT 连接助手 ---

def connect() -> mqtt_client.Client:
    client = mqtt_client.Client(f"monitor-{int(time.time()*1000)%100000}")
    if MQTT_USER:
        client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=20)
    return client

# --- 功能 A：发布状态 ---
if args.status:
    payload = {
        "service": args.service,
        "status": args.status,
        "timestamp": int(time.time())
    }
    if args.pid:
        payload["pid"] = args.pid
    if args.extra:
        try:
            payload.update(json.loads(args.extra))
        except json.JSONDecodeError:
            payload["extra"] = args.extra
    topic = f"{TOPIC_PREFIX}/{args.service}"

    cli = connect()
    cli.publish(topic, json.dumps(payload), retain=True)
    cli.disconnect()
    sys.exit(0)

# --- 功能 B：等待 Topic online ---
if args.check_topic_online:
    topic = args.check_topic_online
    received = {
        "flag": False
    }

    def on_message(_cli, _ud, msg):
        if msg.payload.decode() == "online":
            received["flag"] = True
            _cli.disconnect()

    cli = connect()
    cli.on_message = on_message
    cli.subscribe(topic, qos=0)

    start = time.time()
    cli.loop_start()
    try:
        while time.time() - start < args.timeout:
            if received["flag"]:
                cli.loop_stop()
                sys.exit(0)
            time.sleep(0.2)
        cli.loop_stop()
        sys.exit(1)  # 超时未收到 online
    except KeyboardInterrupt:
        cli.loop_stop()
        sys.exit(1)

# 若未匹配任何功能
parser.print_help()
sys.exit(1)

