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
| ②  | 进入容器打包    | 通过 `in_proot()` 执行 `tar -czf`，压缩 `/root/.homeassistant` 全量文件 |
| ③  | 日志 & MQTT | 所有输出写入独立日志；调用 `monitor.py` 上报备份结果                            |
| ④  | 自动清理      | 保留最新 **3** 份备份与日志（可调）                                        |

备份文件示例：

```
/sdcard/isgbackup/ha/homeassistant_backup_20250710-015230.tar.gz
```

日志文件示例：

```
/sdcard/isgbackup/ha/backup_20250710-015230.log
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
* MQTT 主题 `isg/status/home_assistant` 发布一条形如：

  ```json
  {
    "service":"home_assistant",
    "status":"success",
    "file":"/sdcard/isgbackup/ha/homeassistant_backup_20250710-015230.tar.gz",
    "size_kb":84512,
    "duration":17,
    "log":"/sdcard/isgbackup/ha/backup_20250710-015230.log",
    "timestamp":1720573950
  }
  ```

---

### 3. 环境变量一览

| 变量             | 默认值                    | 作用                            |
| -------------- | ---------------------- | ----------------------------- |
| `PROOT_DISTRO` | `ubuntu`               | 容器名称（`proot-distro list` 可查看） |
| `HA_DIR`       | `/root/.homeassistant` | HA 配置目录（容器内部路径）               |
| `BACKUP_DIR`   | `/sdcard/isgbackup/ha` | 备份与日志存放目录                     |
| `KEEP_BACKUPS` | `3`                    | 备份/日志最多保留数量                   |

> 只需在脚本前临时导出即可，例如：
>
> ```bash
> export KEEP_BACKUPS=10
> bash backup.sh
> ```

---

### 4. 定时备份示例

**(1) cron in proot‑ubuntu**
在容器内安装 `cron` 并添加：

```cron
0 3 * * * /data/data/com.termux/files/home/services/home_assistant/backup.sh
```

每天 03:00 备份一次。

**(2) runit in Termux**
创建 `service/ha-backup/run`：

```bash
#!/data/data/com.termux/files/usr/bin/bash
exec every 3600 /data/data/com.termux/files/home/services/home_assistant/backup.sh
```

---

### 5. 故障排查

| 情况              | 解决办法                                           |
| --------------- | ---------------------------------------------- |
| MQTT 无状态        | 检查 `monitor.py` 里 MQTT 认证是否正确；查看 `.log`        |
| 备份文件过小 / 空      | 确认容器路径 `HA_DIR` 是否正确，或 Home Assistant 停止导致目录为空 |
| `tar_failed` 上报 | 大概率磁盘已满 (`df -h /sdcard`)，或路径权限不足              |

---

### 6. 恢复（restore）提示

备份仅覆盖 **配置 & 数据库** 文件；如需恢复：

1. 停止 Home Assistant：`bash stop.sh`
2. 解压备份。

```bash
cd /root/.homeassistant
rm -rf *
 tar -xzf /sdcard/isgbackup/ha/homeassistant_backup_20250710-015230.tar.gz -C .
```

3. 重新启动服务：`bash start.sh`

---

### 7. 常见问题

**Q: 备份很慢怎么办？**
A: 可在容器内禁用 `tts/`、`www/` 等大文件目录，或先 `tar --exclude=tts`。

**Q: 如何改变压缩格式？**
A: 将 `tar -czf` 改成 `tar -C … | zstd > file.tar.zst`，并修改文件后缀。

---

> **如有疑问或改进建议**，请联系运维或在脚本仓库提 Issue。
