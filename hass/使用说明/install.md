
## Home Assistant 安装脚本设计规范 (`install.sh`)

> 脚本路径:
> `/data/data/com.termux/files/home/servicemanager/hass/install.sh`

> 适用环境:
>
> * Termux + Proot-Distro `ubuntu`
> * Home Assistant 安装自动化、稳定化脚本

---

### 1. 执行目标

* 检测 `/root/homeassistant` 虚拟环境是否存在，如果存在则调用 `uninstall.sh` 前置卸载
* 创建 Python venv + 基础依赖 + Home Assistant 指定版本
* 验证首启是否成功，确保 HA 可用
* MQTT 上报 `installing` → `success` / `failed`
* 日志输出到 `/data/data/com.termux/files/home/servicemanager/hass/logs/install.log`

---

### 2. 功能概览

| 步骤          | 操作内容                                                       |
| ----------- | ---------------------------------------------------------- |
| 系统依赖        | apt update + ffmpeg + libturbojpeg                         |
| Python venv | `/root/homeassistant` + pip 升级 + numpy/mutagen/pillow/等基础包 |
| HA 安装       | pip install `homeassistant==2025.5.3`                      |
| 首启检测        | 启动 hass 进程，检测 8123 端口结果                                    |
| 压缩优化        | pip install zlib-ng isal --no-binary \:all:                |
| 配置补丁        | `logger: critical` + `http.use_x_frame_options: false`     |
| MQTT 上报     | topic: `isg/install/hass/status`                           |

---

### 3. MQTT 上报示例

```json
{
  "service": "home_assistant",
  "status": "success",
  "version": "2025.5.3",
  "log": "/data/data/com.termux/files/home/servicemanager/hass/logs/install.log",
  "timestamp": 1720574100
}
```

---

### 4. 执行流程逻辑

```bash
# 如存在前版本则先卸载
[ -d /root/homeassistant ] && bash uninstall.sh

# 1. 系统依赖
apt update && apt install -y ffmpeg libturbojpeg

# 2. Python venv
python3 -m venv /root/homeassistant
source /root/homeassistant/bin/activate
pip install --upgrade pip
pip install numpy mutagen pillow aiohttp_fast_zlib
pip install aiohttp==3.10.8 attrs==23.2.0 PyTurboJPEG

# 3. 安装 HA
pip install homeassistant==2025.5.3

# 4. 首启检测
hass & PID=$!
sleep 最多 90 分钟，检测 8123 是否开放
如超时前杀死进程并上报 failed

# 5. 压缩优化
pip install zlib-ng isal --no-binary :all:

# 6. 配置补丁
向 configuration.yaml 写 logger + http 设置

# 7. MQTT 上报 success + 完成版本检查
```

---

### 5. 环境变量

| 名称             | 默认值                      | 说明                   |
| -------------- | ------------------------ | -------------------- |
| `PROOT_DISTRO` | `ubuntu`                 | 指定 proot-distro 名称   |
| `BACKUP_DIR`   | `/sdcard/isgbackup/hass` | 日志/备份目录              |
| `HASS_VERSION` | `2025.5.3`               | 指定 Home Assistant 版本 |

---

### 6. 设计要点

* 首先判断旧 venv，确保环境稳定重装
* 可重复执行，并有 MQTT 状态反馈
* 首启检测监控服务是否实际可用
* 配置补丁确保 HA 在 iframe/静默日志下稳定运行
* 解耦 backup.sh/上报和 autocheck.sh 进行自检功能联动

---

> 推荐配合升级前 backup.sh，或配合 `autocheck.sh` 自动更新使用




## Home Assistant 安装脚本使用说明 (`install.sh`)提示词

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/install.sh`

> **运行目标**
> * 首先检查proot-distro ubuntu里/root/homeassistant 虚拟环境是否存在，如果存在，需要先执行uninstall.sh卸载home assistant，并删除改虚拟环境
> * 在 ** proot-distro ubuntu ** 中创建 Python 虚拟环境并安装 Home Assistant `2025.5.3` 及依赖。
> * 全程输出日志到 `/sdcard/isgbackup/hass/install_<时间>.log`
> * 通过termux Mosquitto cli 上报 MQTT，主题：isg/install/hass/status installing → installed / failed。
---

### 功能概览
> * 系统依赖： apt update + 安装 ffmpeg， libturbojpeg， 
> * Python venv：/root/homeassistant` 虚拟环境 + pip install --upgrade pip ，基础依赖 (numpy mutagen pillow aiohttp_fast_zlib aiohttp==3.10.8 attrs==23.2.0 PyTurboJPEG）
> * 安装 HA：pip install homeassistant==<特定版本>
> * 首次启动：使用start.sh 确认HA启动成功
> * 优化压缩：安装 `zlib-ng isal` 源码版，提高 zlib 性能
> * 配置补丁：`configuration.yaml` 添加 `logger: critical` 与 `http.use_x_frame_options: false`
> * 完成上报：MQTT `success`，payload 包含版本号与日志路径
> * MQTT上报：通过termux Mosquitto cli 上报 MQTT，主题：isg/backup/hass/status backuping → success / failed
> * MQTT broker：登陆信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml 获取
> * 执行成功后 MQTT 示例：

```json
{
  "service":"home_assistant",
  "status":"success",
  "version":"2025.5.3",
  "log":"/data/data/com.termux/files/home/servicemanager/hass/logs/install.log",
  "timestamp":1720574100
}
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

