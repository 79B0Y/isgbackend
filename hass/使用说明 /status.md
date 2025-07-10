## Home Assistant 状态检测脚本使用说明 (`status.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/status.sh`

> **检测维度**
>
> 1. **进程存在**：`pgrep -f '[h]omeassistant'`
> 2. 计算进程运行时长，
> 3. **端口可连**：`nc -z 127.0.0.1 8123`
> 4. 通过termux Mosquitto cli 上报 MQTT, 主题：isg/status/hass/status
> 5. 通过MQTT 上报： 当前进程，进程运行时长，端口连接状态，运行状态（running，starting，stopped）
> 6. MQTT broker信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml获取
---

### 1. 输出与退出码

| 输出文本       | 含义                 | 退出码   |
| ---------- | ------------------ | ----- |
| `running`  | 全部检测通过             | **0** |
| `starting` | 进程存在，但端口未就绪 | **2** |
| `stopped`  | 进程不存在，或脚本未安装       | **1** |

> 脚本还支持：
>
> * `--json`：输出 `{"status":"running","pid":12345,"runtime":35 mins}`
> * `--quiet`：不输出文本，仅通过退出码判断。

---


### 4. 与其他脚本联动

* **`backup.sh` / `autocheck.sh`** 在执行前会调用 `status.sh --quiet` 判断是否处于 `running`。

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

> **有任何改进需求**，请提交 PR 或联系脚本维护者。
