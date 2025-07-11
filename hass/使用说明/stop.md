## Home Assistant 停止脚本设计规范 (`stop.sh`)

> 脚本路径:
> `/data/data/com.termux/files/home/servicemanager/hass/stop.sh`

> 适用场景:
>
> * 手动或自动停止 Home Assistant
> * 和 uninstall / restore / update / autocheck 配合使用

---

### 1. 功能概览

| 步骤           | 操作说明                                                                     |
| ------------ | ------------------------------------------------------------------------ |
| 发送停止指令       | 写入: `echo d > $LSVDIR/hass/supervise/control`                            |
| 状态检测         | 调用 `status.sh` 确认服务已停止                                                   |
| 创建 .disabled | 在服务目录下创建 `.disabled`，防止 autocheck 重启                                     |
| 日志输出         | 写入: `/data/data/com.termux/files/home/servicemanager/hass/logs/stop.log` |
| MQTT 上报      | 为 `isg/run/hass/status` ：`stoping` → `stoped` / `failed` ，包含 `message`   |
| Broker 配置    | 从 `configuration.yaml` 读取 MQTT 连接设置                                      |

---

### 2. 执行流程

```bash
# 1. 发送停止命令
echo d > $LSVDIR/hass/supervise/control
mqtt_report "isg/run/hass/status" '{"status": "stoping"}'

# 2. 检测状态
for i in {1..30}; do
  if bash status.sh --quiet; then
    sleep 10  # 继续等待端口锁止
  else
    break
  fi
done

# 3. 确认结果
if bash status.sh --quiet; then
  mqtt_report "isg/run/hass/status" '{"status": "failed", "message": "Service is still running after stop attempt."}'
else
  touch /data/data/com.termux/files/home/servicemanager/hass/.disabled
  mqtt_report "isg/run/hass/status" '{"status": "stoped", "message": "Service stopped and .disabled flag set."}'
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

* 日志文件: `stop.log`
* 最多保留 500 条，超过自动删除
* 停止结果上报 MQTT，带英文 `message` 描述

---

### 5. 设计要点

* 统一停止操作模型，配合 autocheck / uninstall / restore
* 通过 `.disabled` 标志确保未经授权不再重启
* 状态上报 + 错误描述方便前端时常监控
* 支持重复执行，免置处理先实施

---

> 推荐在升级，还原，卸载之前使用本脚本停止服务





## Home Assistant 启动脚本使用说明 (`stop.sh`)提示词

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/stop.sh`

> **脚本作用**
>
> * 通过启动服务 echo d > $LSVDIR/hass/supervise/control 来停止home assistant
> * 日志: 所有输出写入独立日志，日志存入/data/data/com.termux/files/home/servicemanager/<service_id>/logs/<script>.log, 保存最近500条
> * 停止确认：停止home assistant运行后，通过status.sh脚本查看服务是否在运行
> * MQTT上报：通过termux Mosquitto cli 上报 MQTT，主题：。主题：isg/run/hass/status `stoping` → `stoped` / `failed`。
> * MQTT broker：登陆信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml 获取
> * 停止后增加标志位 .disable, MQTT 上报message
