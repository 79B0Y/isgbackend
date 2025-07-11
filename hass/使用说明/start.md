## Home Assistant 启动脚本设计规范 (`start.sh`)

> 脚本路径:
> `/data/data/com.termux/files/home/servicemanager/hass/start.sh`

> 适用环境:
>
> * Termux + Proot Ubuntu
> * 统一服务启动调用脚本

---

### 1. 功能概览

| 步骤        | 操作内容                                                                          |
| --------- | ----------------------------------------------------------------------------- |
| 启动服务      | 通过 isgservicemonitor 写入 control 文件: `echo u > $LSVDIR/hass/supervise/control` |
| 状态检测      | 调用 `status.sh` 确认是否达到 `running` 状态                                            |
| 日志输出      | 输出自己日志 + status 检查结果自动输入 log 文件                                               |
| MQTT 上报   | 首先上报 `starting`，确认成功或失败后上报 `running` / `failed`                               |
| Broker 配置 | 从 `configuration.yaml` 读取 MQTT 配置                                             |
| 错误语言      | 若启动失败，上报英文 message 与错误日志                                                      |

---

### 2. 执行流程

```bash
# 1. 启动服务
echo u > $LSVDIR/hass/supervise/control

# 2. 上报 MQTT: starting
mqtt_report "isg/run/hass/status" '{"status": "starting"}'

# 3. 检测 running 状态
for i in {1..30}; do
  bash status.sh --quiet && break
  sleep 10
done

# 4. 确定状态
if bash status.sh --quiet; then
  mqtt_report "isg/run/hass/status" '{"status": "running"}'
else
  mqtt_report "isg/run/hass/status" '{"status": "failed", "message": "Service failed to reach running state."}'
fi
```

---

### 3. 环境变量

| 名称           | 默认值                                                          | 说明            |
| ------------ | ------------------------------------------------------------ | ------------- |
| `BACKUP_DIR` | `/data/data/com.termux/files/home/servicemanager/hass/logs/` | 日志输出目录        |
| `MAX_TRIES`  | `30` (interval 10s)                                          | 最大检测次数 = 5 分钟 |

---

### 4. 日志管理

* 日志文件: `/data/data/com.termux/files/home/servicemanager/hass/logs/start.log`
* 最多保留 500 条日志，超过自动删除
* 运行输出 (stdout/stderr) 延传至 `hass_runtime.log`

---

### 5. 设计要点

* 上报状态通过 MQTT，方便 Android/Web 端监控
* 检测启动成功不依靠命令执行是否成功，而是实际运行状态
* 若失败自动上报英文错误说明，便于日志分析

---

> 推荐配合 `autocheck.sh` 定期执行，或在安装/还原后使用调用





## Home Assistant 启动脚本使用说明 (`start.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/start.sh`

> **脚本作用**
>
> * 通过isgservicemonitor启动服务，启动命令： echo u > $LSVDIR/hass/supervise/control 来启动home assistant
> * 日志: 所有输出写入独立日志，日志存入/data/data/com.termux/files/home/servicemanager/<service_id>/logs/<script>.log, 保存最近500条
> * 启动home assistant运行后，通过status.sh脚本查看服务是否在运行
> * 通过termux Mosquitto cli 上报 MQTT，主题：isg/run/hass/status `starting` → `running` / `failed`。
> * MQTT broker：登陆信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml 获取
> * 错误消息：通过MQTT message上报，message为英文
