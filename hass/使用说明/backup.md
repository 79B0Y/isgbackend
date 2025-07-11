## Home Assistant 备份脚本设计规范 (`backup.sh`)

> 脚本路径:
> `/data/data/com.termux/files/home/servicemanager/hass/backup.sh`

> 适用环境:
>
> * 脚本运行于 Termux 宿主系统
> * Home Assistant 数据位于 Proot 容器 `ubuntu` 内的 `/root/.homeassistant`

---

### 1. 功能概览

| 步骤        | 操作说明                                                                                        |
| --------- | ------------------------------------------------------------------------------------------- |
| 检测运行      | 调用 `status.sh` 确认服务处于 `running`，否则退出                                                        |
| 打包备份      | 通过 `in_proot()` 执行 `tar -czf` ，压缩 `/root/.homeassistant`，输出文件到 `/sdcard/isgbackup/hass/`    |
| 日志输出      | 将脚本输出写入: `/data/data/com.termux/files/home/servicemanager/hass/logs/backup.log` (500 条日志保留) |
| MQTT 上报   | 上报为 `isg/backup/hass/status` ，包括 `backuping` → `success` / `failed`                         |
| Broker 配置 | 从 `/data/data/com.termux/files/home/servicemanager/configuration.yaml` 获取 MQTT 连接信息         |
| 备份保留      | 最多保留 3 份 .tar.gz + 相关日志，超过自动删除                                                              |

---

### 2. 执行示例

#### 备份文件格式:

```
/sdcard/isgbackup/hass/homeassistant_backup_20250710-015230.tar.gz
```

#### 日志文件:

```
/data/data/com.termux/files/home/servicemanager/hass/logs/backup.log
```

#### MQTT 成功上报示例:

```json
{
  "service": "hass",
  "status": "success",
  "file": "/sdcard/isgbackup/hass/homeassistant_backup_20250710-015230.tar.gz",
  "size_kb": 84512,
  "duration": 17,
  "log": "/data/data/com.termux/files/home/servicemanager/hass/logs/backup.log",
  "timestamp": 1720573950
}
```

---

### 3. 环境变量支持

| 名称             | 默认值                      | 说明                  |
| -------------- | ------------------------ | ------------------- |
| `PROOT_DISTRO` | `ubuntu`                 | Proot 容器名称          |
| `HA_DIR`       | `/root/.homeassistant`   | Home Assistant 配置目录 |
| `BACKUP_DIR`   | `/sdcard/isgbackup/hass` | 压缩文件 & 日志输出目录       |
| `KEEP_BACKUPS` | `3`                      | 备份文件最多保留数           |

---

### 4. 设计策略

* 先检测运行状态，避免备份不完整
* 打包使用 tar.gz，保障级联安全
* 日志 + MQTT 形成双系监控，便于 Web/App 同步告警
* 支持用户自定义容器名和保留数，适配不同实际场景

---

> 推荐配合 `autocheck.sh` 进行时间规则备份，或在升级/还原前手动触发。









## Home Assistant 备份脚本使用说明 (`backup.sh`)提示词

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/backup.sh`

> **适用环境**
>
> * 脚本运行在 **Termux 宿主系统**
> * Home Assistant 数据位于 **proot‑distro ubuntu /root/.homeassistant/

---

### 1. 功能概览
> * 检查运行状态: 调用 `status.sh`，只有服务处于 `running` 时才继续备份
> * 进入容器打包: 通过 `in_proot()` 执行 `tar -czf`，压缩 `/root/.homeassistant` 全量文件，存入/sdcard/isgbackup/hass/
> * 日志: 所有输出写入独立日志，日志存入/data/data/com.termux/files/home/servicemanager/<service_id>/logs/<script>.log, 保存最近500条
> * MQTT上报：通过termux Mosquitto cli 上报 MQTT，主题：isg/backup/hass/status `backuping` → `success` / `failed`
> * MQTT broker：登陆信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml 获取
> * 错误消息：通过MQTT message上报，message为英文
> * 自动清理：保留最新 **3** 份备份
> * 备份文件示例：
```
/sdcard/isgbackup/hass/homeassistant_backup_20250710-015230.tar.gz
```
> * 日志文件示例：
```
/data/data/com.termux/files/home/servicemanager/hass/logs/backup.log
```
> * 执行成功后：
    MQTT 主题 `isg/status/hass` 发布一条形如：
  ```json
  {
    "service":"hass",
    "status":"success",
    "file":"/sdcard/isgbackup/hass/homeassistant_backup_20250710-015230.tar.gz",
    "size_kb":84512,
    "duration":17,
    "log":"/data/data/com.termux/files/home/servicemanager/hass/logs/backup.log",
    "timestamp":1720573950
  }
  ```
