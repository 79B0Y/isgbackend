## Home Assistant 备份脚本使用说明 (`backup.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/backup.sh`

> **适用环境**
>
> * 脚本运行在 **Termux 宿主系统**
> * Home Assistant 数据位于 **proot‑distro 容器**（默认名称：`ubuntu`）

---

### 1. 功能概览

| 步骤 | 动作        | 说明                                                           |
| -- | --------- | ------------------------------------------------------------ |
| ①  | 检查运行状态    | 调用 `status.sh`，只有服务处于 `running` 时才继续备份                       |
| ②  | 进入容器打包    | 通过 `in_proot()` 执行 `tar -czf`，压缩 `/root/.homeassistant` 全量文件，存入/sdcard/isgbackup/hass/ |
| ③  | 日志   | 所有输出写入独立日志，日志存入 存入/sdcard/isgbackup/hass/；                           |
| ④  | MQTT      | 通过termux Mosquitto cli 上报 MQTT，主题：isg/backup/hass/status `backuping` → `success` / `failed`。                                       |
| 5  | 自动清理      | 保留最新 **3** 份备份与日志（可调）                                        |
MQTT broker信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml获取
备份文件示例：

```
/sdcard/isgbackup/hass/homeassistant_backup_20250710-015230.tar.gz
```

日志文件示例：

```
/sdcard/isgbackup/hass/backup_20250710-015230.log
```

---

### 2. 快速使用

```bash
# 手动备份（最常用）
bash backup.sh

# 临时覆盖容器名、保留份数
PROOT_DISTRO=ubuntu-arm KEEP_BACKUPS=5 bash backup.sh
```

执行成功后：

* 终端输出即日志内容；
* MQTT 主题 `isg/status/hass` 发布一条形如：

  ```json
  {
    "service":"hass",
    "status":"success",
    "file":"/sdcard/isgbackup/hass/homeassistant_backup_20250710-015230.tar.gz",
    "size_kb":84512,
    "duration":17,
    "log":"/sdcard/isgbackup/hass/backup_20250710-015230.log",
    "timestamp":1720573950
  }
  ```

---

### 3. 环境变量一览

| 变量             | 默认值                    | 作用                            |
| -------------- | ---------------------- | ----------------------------- |
| `PROOT_DISTRO` | `ubuntu`               | 容器名称（`proot-distro list` 可查看） |
| `HA_DIR`       | `/root/.homeassistant` | HA 配置目录（容器内部路径）               |
| `BACKUP_DIR`   | `/sdcard/isgbackup/hass` | 备份与日志存放目录                     |
| `KEEP_BACKUPS` | `3`                    | 备份/日志最多保留数量                   |

> 只需在脚本前临时导出即可，例如：
>
> ```bash
> export KEEP_BACKUPS=10
> bash backup.sh
> ```

---
