## Home Assistant 升级脚本使用说明 (`update.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/update.sh`

> **脚本功能**
>
> * 将 `/root/homeassistant` 虚拟环境中的 Home Assistant 升级或降级到 **指定版本**。
> * **版本号来源**：`TARGET_VERSION` 环境变量，或脚本第一个参数。
> * 日志: 所有输出写入独立日志，日志存入/data/data/com.termux/files/home/servicemanager/<service_id>/logs/<script>.log, 保存最近500条
> * 通过termux Mosquitto cli 上报 MQTT，主题：isg/update/hass/status `updating` → `success` / `failed`。
> * MQTT broker信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml获取
> * 错误消息：通过MQTT message上报，message为英文
> * 升级脚本
>
```bash
proot-distro login ubuntu << 'EOF'

log_step() {
  echo -e "\n[STEP] $1"
}

log_step "激活虚拟环境"
source /root/homeassistant/bin/activate

log_step "升级 ensurepip（确保 pip 可用）"
python -m ensurepip --upgrade

log_step "升级 pip"
pip install --upgrade pip

log_step "升级 Home Assistant 到 2025.7.1"
pip install --upgrade homeassistant==2025.7.1

log_step "验证版本"
hass --version

log_step "✅ 升级完成"

EOF
```
