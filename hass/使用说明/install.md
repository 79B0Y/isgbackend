## Home Assistant 安装脚本使用说明 (`install.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/install.sh`

> **运行目标**
>
> * 在 **proot-distro 容器 (ubuntu)** 中创建 Python 虚拟环境并安装 Home Assistant `2025.5.3` 及依赖。
> * 全程输出日志到 `/sdcard/isgbackup/hass/install_<时间>.log`
> * 通过termux Mosquitto cli 上报 MQTT，主题：isg/install/hass/status installing → installed / failed。
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
| 完成上报        | MQTT `success`，payload 包含版本号与日志路径                                      |

---


执行成功后 MQTT 示例：

```json
{
  "service":"home_assistant",
  "status":"success",
  "version":"2025.5.3",
  "log":"/sdcard/isgbackup/hass/install_20250710-021500.log",
  "timestamp":1720574100
}
```

---

### 3. 环境变量

| 变量             | 默认值                    | 说明                           |
| -------------- | ---------------------- | ---------------------------- |
| `PROOT_DISTRO` | `ubuntu`               | 容器名 (`proot-distro list`)    |
| `BACKUP_DIR`   | `/sdcard/isgbackup/hass` | 日志与备份根目录                     |
| `HASS_VERSION` | `2025.5.3`             | 安装的 Home Assistant 版本 (如需切换) |

> 示例：
>
> ```bash
> HASS_VERSION=2025.6.2 bash install.sh
> ```

---

### 4. 日志查看

* 安装过程中控制台输出即写入日志。
* 成功路径示例：`/sdcard/isgbackup/hass/install_20250710-021500.log`

常用 grep：

```bash
grep -i error install_*.log
```

安装的脚本：
# ------------------------------------------------------------
# 1. 更新系统并安装依赖
log_step "更新 apt 索引并安装系统依赖 (ffmpeg libturbojpeg)"
run_or_fail "apt update" "apt update -y"
run_or_fail "安装 ffmpeg libturbojpeg" "apt install -y ffmpeg libturbojpeg"

# 2. 创建并初始化 Python 虚拟环境
log_step "创建 Python 虚拟环境 /root/homeassistant"
run_or_fail "创建 venv" "python3 -m venv /root/homeassistant"

log_step "安装 Python 库 (numpy mutagen pillow 等)"
PY_SETUP='source /root/homeassistant/bin/activate && \
  pip install --upgrade pip && \
  pip install numpy mutagen pillow aiohttp_fast_zlib && \
  pip install aiohttp==3.10.8 attrs==23.2.0 && \
  pip install PyTurboJPEG'
run_or_fail "安装基础依赖" "$PY_SETUP"

# 3. 安装 Home Assistant
log_step "安装 Home Assistant 2025.5.3"
run_or_fail "pip 安装 Home Assistant" "source /root/homeassistant/bin/activate && pip install homeassistant==2025.5.3"

# 4. 首启生成配置目录
log_step "首次启动 Home Assistant，生成配置目录"
HASS_PID=$(in_proot "source /root/homeassistant/bin/activate && hass & echo \$!")
echo "[INFO] 初始化进程 PID: $HASS_PID"

MAX_TRIES=90; COUNT=0
while (( COUNT < MAX_TRIES )); do
    if nc -z 127.0.0.1 8123 2>/dev/null; then
        echo "[INFO] Home Assistant Web 已就绪"
        break
    fi
    COUNT=$((COUNT+1)); sleep 60
done
if (( COUNT >= MAX_TRIES )); then
    echo "[ERROR] 初始化超时"
    in_proot "kill $HASS_PID || true"
    mqtt_report install_failed "{\"error\":\"init_timeout\",\"log\":\"$LOG_FILE\"}"
    exit 1
fi

# 5. 终止并优化压缩库
log_step "终止首次启动进程并安装 zlib-ng / isal"
in_proot "kill $HASS_PID"
run_or_fail "安装 zlib-ng isal" "source /root/homeassistant/bin/activate && pip install zlib-ng isal --no-binary :all:"

# 6. 调整 configuration.yaml
log_step "配置 logger 为 critical & 允许 iframe"
in_proot "grep -q '^logger:' /root/.homeassistant/configuration.yaml || echo -e '\nlogger:\n  default: critical' >> /root/.homeassistant/configuration.yaml"
in_proot "grep -q 'use_x_frame_options:' /root/.homeassistant/configuration.yaml || echo -e '\nhttp:\n  use_x_frame_options: false' >> /root/.homeassistant/configuration.yaml"

# 7. 完成并上报
VERSION_STR=$(in_proot "source /root/homeassistant/bin/activate && hass --version")
log_step "安装完成，Home Assistant 版本: $VERSION_STR"

echo "======== Home Assistant 安装脚本结束 ========"

