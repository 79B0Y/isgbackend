## Home Assistant 安装脚本使用说明 (`install.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/services/home_assistant/install.sh`

> **运行目标**
>
> * 在 **proot-distro 容器 (ubuntu)** 中创建 Python 虚拟环境并安装 Home Assistant `2025.5.3` 及依赖。
> * 全程输出日志到 `/sdcard/isgbackup/ha/install_<时间>.log` 并通过 `monitor.py` 发送 MQTT 上报。

---

### 1. 功能流程

| 步骤          | 描述                                                                             |
| ----------- | ------------------------------------------------------------------------------ |
| 系统依赖        | `apt update` + 安装 `ffmpeg libturbojpeg`                                        |
| Python venv | `/root/homeassistant` 虚拟环境 + 基础依赖 (numpy、pillow…）                              |
| 安装 HA       | `pip install homeassistant==2025.5.3`                                          |
| 首次启动        | 后台运行 `hass`，等待 8123 端口就绪（最多 90 分钟）                                             |
| 优化压缩        | 安装 `zlib-ng isal` 源码版，提高 zlib 性能                                               |
| 配置补丁        | `configuration.yaml` 添加 `logger: critical` 与 `http.use_x_frame_options: false` |
| 完成上报        | MQTT `install_success`，payload 包含版本号与日志路径                                      |

---

### 2. 快速使用

```bash
# 默认容器 ubuntu
bash install.sh

# 自定义容器名 + 日志输出目录
PROOT_DISTRO=ubuntu-arm BACKUP_DIR=/sdcard/ha_backup bash install.sh
```

执行成功后 MQTT 示例：

```json
{
  "service":"home_assistant",
  "status":"install_success",
  "version":"2025.5.3",
  "log":"/sdcard/isgbackup/ha/install_20250710-021500.log",
  "timestamp":1720574100
}
```

---

### 3. 环境变量

| 变量             | 默认值                    | 说明                           |
| -------------- | ---------------------- | ---------------------------- |
| `PROOT_DISTRO` | `ubuntu`               | 容器名 (`proot-distro list`)    |
| `BACKUP_DIR`   | `/sdcard/isgbackup/ha` | 日志与备份根目录                     |
| `HASS_VERSION` | `2025.5.3`             | 安装的 Home Assistant 版本 (如需切换) |

> 示例：
>
> ```bash
> HASS_VERSION=2025.6.2 bash install.sh
> ```

---

### 4. 日志查看

* 安装过程中控制台输出即写入日志。
* 成功路径示例：`/sdcard/isgbackup/ha/install_20250710-021500.log`

常用 grep：

```bash
grep -i error install_*.log
```

---

### 5. 故障排查

| 场景                       | 解决方案              |
| ------------------------ | ----------------- |
| MQTT 上报 `install_failed` | 查看日志文件最后几行，定位失败步骤 |
| 超时 (`init_timeout`)      | 1) 检查设备性能/磁盘      |

2. 增大 `MAX_TRIES` 或减小 `sleep` 间隔 |
   \| `pip install` 速度慢 | 临时换源：`PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple bash install.sh` |
   \| 端口 8123 占用 | `lsof -i:8123` 查看冲突进程 |

---

### 6. 后续操作

* **启动**：`bash start.sh`（脚本目录同级）
* **状态**：`bash status.sh`
* **备份**：`bash backup.sh`
* **自检**：`bash autocheck.sh`

---

> 如需自定义 Python 依赖或替换为 Docker 安装，可 fork 脚本自行修改 `run_or_fail` 调用。
