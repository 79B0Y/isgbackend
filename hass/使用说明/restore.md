edr## Home Assistant 还原脚本说明 (`restore.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/restore.sh`

> **脚本功能**
>
> * 从 **最新备份** `homeassistant_backup_*.tar.gz` 还原 Home Assistant 配置；若无备份则使用 `homeassistant_original.tar.gz`。
> * 自动停止服务 → 清空配置 → 解压备份 → 重启服务。
> * 过程日志写入 `/sdcard/isgbackup/hass/restore_<时间>.log`。
> * 通过termux Mosquitto cli 上报 MQTT, 主题：isg/restore/hass/status `restoring` → `success` / `failed`。
> * 自动清理	保留最新 3 份备份与日志（可调）
> * MQTT broker信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml获取
---

### 1. 备份选择逻辑

1. **指定参数**：`bash restore.sh /path/to/backup.tar.gz`
2. **自动选择**：无参数时，脚本会在 `/sdcard/isgbackup/ha/` 找最新时间戳的 `homeassistant_backup_*.tar.gz`。
3. **默认备份**：若找不到任何备份，则尝试读取 `homeassistant_original.tar.gz`（初始镜像）。

---

### 2. 快速使用

```bash
# 使用最新备份自动还原
bash restore.sh

# 指定备份文件
bash restore.sh homeassistant_backup_20250710-030000.tar.gz
```
也可以指定不通名称格式的 ***.tar.gz


成功 MQTT 示例：

```json
{
  "service":"hass",
  "status":"success",
  "file":"/sdcard/isgbackup/hass/homeassistant_backup_20250710-030000.tar.gz",
  "log":"/sdcard/isgbackup/hass/restore_20250710-031000.log",
  "timestamp":1720575060
}
```

---

### 3. 环境变量

| 变量             | 默认值                    | 说明                         |
| -------------- | ---------------------- | -------------------------- |
| `PROOT_DISTRO` | `ubuntu`               | 容器名称 (`proot-distro list`) |
| `BACKUP_DIR`   | `/sdcard/isgbackup/hass` | 备份与日志根目录                   |

---

### 4. 日志文件

* 还原过程：`restore_<timestamp>.log`
* 运行日志：还原后会由 `start.sh` 继续写入 `hass_runtime.log`

常用查看：

```bash
tail -f /sdcard/isgbackup/hass/restore_*.log
```

---

### 5. 故障排查

| 场景           | 解决方案                                                  |
| ------------ | ----------------------------------------------------- |
| `no_backup`  | 备份目录为空 → 检查路径或先执行 `backup.sh`                         |
| `tar_failed` | 备份损坏或磁盘空间不足；确认文件完整 & `df -h`                          |
| 服务启动失败       | 查看 `hass_runtime.log`，必要时执行 `stop.sh`、`start.sh` 手动检验 |

---

### 6. 还原前建议

> * **强烈推荐**：在执行还原前先运行 `backup.sh` 生成最新备份，以防回滚失败导致数据丢失。
> * 确保设备电源与网络稳定，解压过程中切勿断电或杀进程。

---

> **备注**：还原脚本不会回退虚拟环境中的 Home Assistant 版本。如果需要同时回退版本，请先执行 `update.sh <旧版>` 再运行 `restore.sh`。
