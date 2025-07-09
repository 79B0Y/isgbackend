## Home Assistant 状态检测脚本使用说明 (`status.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/services/home_assistant/status.sh`

> **检测维度**
>
> 1. **进程存在**：`pgrep -f '[h]omeassistant'`
> 2. **端口可连**：`nc -z 127.0.0.1 8123`
> 3. **MQTT Online**：订阅保留消息 `homeassistant/status` 并期望 payload=`online`

---

### 1. 输出与退出码

| 输出文本       | 含义                 | 退出码   |
| ---------- | ------------------ | ----- |
| `running`  | 全部检测通过             | **0** |
| `starting` | 进程存在，但端口或 MQTT 未就绪 | **2** |
| `stopped`  | 进程不存在，或脚本未安装       | **1** |

> 脚本还支持：
>
> * `--json`：输出 `{"status":"running","pid":12345}`
> * `--quiet`：不输出文本，仅通过退出码判断。

---

### 2. 快速示例

```bash
# 标准调用，打印状态文本ash status.sh

# 静默模式（仅看退出码）
bash status.sh --quiet && echo OK || echo NG

# JSON 输出
status=$(bash status.sh --json)
```

---

### 3. 环境变量

| 变量           | 默认值                    | 说明                        |
| ------------ | ---------------------- | ------------------------- |
| `MQTT_HOST`  | `127.0.0.1`            | MQTT Broker 地址            |
| `MQTT_PORT`  | `1883`                 | Broker 端口                 |
| `MQTT_USER`  | `admin`                | 用户名                       |
| `MQTT_PASS`  | `admin`                | 密码                        |
| `MQTT_TOPIC` | `homeassistant/status` | Online 状态主题               |
| `PORT`       | `8123`                 | HA Web 端口（脚本内部常量，可手动导出覆盖） |

临时覆盖示例：

```bash
MQTT_HOST=192.168.1.10 MQTT_USER=hauser MQTT_PASS=secret bash status.sh
```

---

### 4. 与其他脚本联动

* **`backup.sh` / `autocheck.sh`** 在执行前会调用 `status.sh --quiet` 判断是否处于 `running`。
* **`monitor.py`** 可据此状态选择发送 `running` / `starting` / `stopped` 上报。

---

### 5. 故障排查

| 情况           | 排查建议                               |
| ------------ | ---------------------------------- |
| 总是 `stopped` | 1) `pgrep -f homeassistant` 手动查看进程 |

2. 如无进程，先启动 HA (`start.sh`) |
   \| `starting` 长时间不变 | 1) `nc -z 127.0.0.1 8123` 检查端口
3. MQTT retainer 未上报 online，确认 `configuration.yaml` 中 `mqtt:` 设置 |
   \| MQTT 检测卡死 | 1) Broker 地址/凭证错误，或未启用保留消息
4. 调整 `MQTT_TIMEOUT` 环境变量 |

---

### 6. 集成到自动化

**示例：在安卓 App 侧定时查询**

```kotlin
val (statusCode, out) = ssh.exec("bash /services/home_assistant/status.sh --json")
val json = JSONObject(out)
when (json.getString("status")) {
    "running"  -> greenLED()
    "starting" -> yellowLED()
    else        -> redLED()
}
```

---

> **有任何改进需求**，请提交 PR 或联系脚本维护者。
