## Home Assistant 状态检测脚本设计规范 (`status.sh`)

> 脚本路径:
> `/data/data/com.termux/files/home/servicemanager/hass/status.sh`

> 适用场景:
>
> * 用于其他脚本 (如 backup / start / autocheck) 进行服务状态判断
> * 支持应用端 MQTT 实时状态管理

---

### 1. 检测项目

| 项目      | 说明                                                             |
| ------- | -------------------------------------------------------------- |
| 进程检测    | `pgrep -f '[h]omeassistant'` 确认是否存在                            |
| 运行时长    | 计算 PID 运行时间                                                    |
| 端口检测    | `nc -z 127.0.0.1 8123` 确认 Web UI 是否可连                          |
| MQTT 上报 | 频道: `isg/status/hass/status` 上报 `running`/`starting`/`stopped` |
| 错误说明    | 若失败，通过 `message` 键进行英文错误上报                                     |

---

### 2. 返回结果 & 选项

| 结果         | 含义               | 选择参数      | 选择效果                      |
| ---------- | ---------------- | --------- | ------------------------- |
| `running`  | 进程存在 + 8123 端口打开 | `--json`  | 以 JSON 格式输出状态、PID、runtime |
| `starting` | 进程存在但端口未开放       | `--quiet` | 不输出文本，仅通过退出码判断            |
| `stopped`  | 进程未启动或连接失败       |           | 默认输出文本，并输出 MQTT           |

> 退出码规范:
>
> * 0: running
> * 1: stopped
> * 2: starting

---

### 3. MQTT 上报示例

```json
{
  "service": "hass",
  "status": "running",
  "pid": 3124,
  "runtime": "42m",
  "port": true,
  "timestamp": 1720574000
}
```

---

### 4. 日志管理

* 日志输入: `/data/data/com.termux/files/home/servicemanager/hass/logs/status.log`
* 日志最多保留 500 条，超过自动删除
* 运行错误上报 MQTT `message`，包含英文描述

---

### 5. 设计要点

* 先查 PID，再确认端口是否已开放，避免假启动
* 支持 shell/脚本 和 MQTT 同时使用
* 上报的状态便于 App 同步显示
* 被 autocheck / backup / start 脚本依赖调用

---

> 推荐在后台断电重启、手动启动/更新/备份前先检测状态


MQTT 上报统一采用
load_mqtt_conf() {
  MQTT_HOST=$(grep -Po '^[[:space:]]*host:[[:space:]]*\K.*' "$CONFIG_FILE" | head -n1)
  MQTT_PORT=$(grep -Po '^[[:space:]]*port:[[:space:]]*\K.*' "$CONFIG_FILE" | head -n1)
  MQTT_USER=$(grep -Po '^[[:space:]]*username:[[:space:]]*\K.*' "$CONFIG_FILE" | head -n1)
  MQTT_PASS=$(grep -Po '^[[:space:]]*password:[[:space:]]*\K.*' "$CONFIG_FILE" | head -n1)
}

mqtt_report() {
  local topic="$1"
  local payload="$2"
  load_mqtt_conf
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" -t "$topic" -m "$payload" || true
  echo "[MQTT] $topic -> $payload" >> "$LOG_FILE"
}


## Home Assistant 状态检测脚本使用说明 (`status.sh`)提示词

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/status.sh`

> **检测维度**
>
> 1. **进程存在**：`pgrep -f '[h]omeassistant'`
> 2. 计算进程运行时长，
> 3. **端口可连**：`nc -z 127.0.0.1 8123`
> 4. MQTT上报：通过termux Mosquitto cli 上报 MQTT，主题：isg/status/hass/status running → starting → stop
> 5. MQTT broker：登陆信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml 获取
> 6. 错误消息：通过MQTT message上报，message为英文
> 7. 日志: 所有输出写入独立日志，日志存入/data/data/com.termux/files/home/servicemanager/<service_id>/logs/<script>.log, 保存最近500条
> 脚本还支持：
> * `--json`：输出 `{"status":"running","pid":12345,"runtime":35 mins}`
> * `--quiet`：不输出文本，仅通过退出码判断
