## Home Assistant 升级脚本使用说明 (`update.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/update.sh`

> **脚本功能**
>
> * 将 `/root/homeassistant` 虚拟环境中的 Home Assistant 升级或降级到 **指定版本**。
> * **版本号来源**：`TARGET_VERSION` 环境变量，或脚本第一个参数。
> * 过程日志写入 `/sdcard/isgbackup/ha/update_<时间>.log`。
> * 通过termux Mosquitto cli 上报 MQTT，主题：isg/update/hass/status `updating` → `success` / `failed`。

---

### 1. 版本来源

| 优先级 | 方式    | 示例                                       |
| --- | ----- | ---------------------------------------- |
| 1   | 命令行参数 | `bash update.sh 2025.6.1`                |
| 2   | 环境变量  | `TARGET_VERSION=2025.6.1 bash update.sh` |

若两者同时指定，以 **命令行参数** 为准。

---

### 2. 执行流程

1. **发送** `updating` MQTT 状态（包含目标版本）。
2. 调用 `stop.sh` **安全停止服务**。
3. 容器内执行：

   ```bash
   source /root/homeassistant/bin/activate &&
   pip install --upgrade --no-cache-dir homeassistant==<version>
   ```
4. 调用 `start.sh` 重启服务并等待 `running` 确认。
5. 上报 `success`（或 `update_failed`）。

---

### 3. 快速使用

```bash
# 升级到 2025.6.1
bash update.sh 2025.6.1

# 降级到 2025.5.0（使用环境变量）
TARGET_VERSION=2025.5.0 bash update.sh
```

成功 MQTT 示例如下：

```json
{
  "service":"home_assistant",
  "status":"success",
  "version":"2025.6.1",
  "log":"/sdcard/isgbackup/hass/update_20250710-022500.log",
  "timestamp":1720574500
}
```

---

### 4. 环境变量

| 变量               | 默认值                    | 说明                        |
| ---------------- | ---------------------- | ------------------------- |
| `PROOT_DISTRO`   | `ubuntu`               | 容器名 (`proot-distro list`) |
| `BACKUP_DIR`     | `/sdcard/isgbackup/hass` | 日志存放目录                    |
| `TARGET_VERSION` | *(无)*                  | 目标版本号（SemVer）             |

---

### 5. 故障排查

| 场景               | 解决方案                                                                      |
| ---------------- | ------------------------------------------------------------------------- |
| `pip_failed`     | ① 检查网络或换镜像源 ② 版本号拼写是否正确                                                   |
| `runtime_not_up` | HA 启动失败，查看 `hass_runtime.log` 定位原因                                        |
| 版本无变化但仍升级        | 可能因 `pip` 缓存残留，脚本已加 `--no-cache-dir`；若仍出现可先 `pip uninstall homeassistant` |

---

### 6. 与其他脚本关系

| 脚本             | 交互  | 说明                                              |
| -------------- | --- | ----------------------------------------------- |
| `stop.sh`      | 调用  | 确保升级前服务停止                                       |
| `start.sh`     | 调用  | 升级后自动重启并移除 `.disabled`                          |
| `autocheck.sh` | 不影响 | `.disabled` 文件不被创建/删除，升级过程中可能出现短暂 `starting` 状态 |

---

> **建议**：升级前先执行一次 `backup.sh` 备份配置，以便故障时快速回滚。
