## Home Assistant 启动脚本使用说明 (`start.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/services/home_assistant/start.sh`

> **脚本作用**
>
> * 在 **proot‑distro 容器** 中后台启动 Home Assistant（SSH 会话断开后仍运行）。
> * 输出启动日志至 `/sdcard/isgbackup/ha/start_<时间>.log`，运行日志至 `hass_runtime.log`。
> * 通过 `monitor.py` 上报 MQTT：`starting` → `running` / `failed`。

---

### 1. 状态流程

| 阶段       | 说明                       | MQTT 上报                        |
| -------- | ------------------------ | ------------------------------ |
| starting | 执行启动命令后立即发布              | `{status:"starting"}`          |
| running  | `status.sh` 连续检查成功       | `{status:"running"}`           |
| failed   | 启动命令失败或 5 分钟内未达到 running | `{status:"failed", error:"…"}` |

---

### 2. 快速使用

```bash
# 默认容器 ubuntu，直接启动
bash start.sh

# 指定容器名与日志目录\PROOT_DISTRO=ubuntu-arm BACKUP_DIR=/sdcard/ha_backup bash start.sh
```

调用成功示例输出：

```
[INFO] hass 已后台启动，日志写入 /sdcard/isgbackup/ha/hass_runtime.log
[OK] Home Assistant 正常运行
```

---

### 3. 环境变量

| 变量             | 默认值                    | 说明                         |
| -------------- | ---------------------- | -------------------------- |
| `PROOT_DISTRO` | `ubuntu`               | 容器名称 (`proot-distro list`) |
| `BACKUP_DIR`   | `/sdcard/isgbackup/ha` | 启动 & 运行日志目录                |
| `MAX_TRIES`    | 30 （脚本内变量）             | 轮询次数，间隔 10 秒=5 分钟          |

---

### 4. 日志说明

| 文件                 | 内容                             |
| ------------------ | ------------------------------ |
| `start_<时间>.log`   | 启动脚本本身输出（包含 MQTT 上报结果）         |
| `hass_runtime.log` | hass 运行时 `stdout/stderr`（持续写入） |

查看最新运行日志：

```bash
tail -f /sdcard/isgbackup/ha/hass_runtime.log
```

---

### 5. 故障排查

| 场景                                | 解决方案                                                                      |
| --------------------------------- | ------------------------------------------------------------------------- |
| MQTT 返回 failed / runtime\_not\_up | 检查 `hass_runtime.log` 是否报错；端口 8123 是否被占用                                  |
| 启动后立刻退出                           | 虚拟环境损坏，可尝试重新 `install.sh` 或 `pip install --force-reinstall homeassistant` |
| 运行日志无内容                           | 确认 `nohup` 路径正确，或检查 SD 卡读写权限                                              |

---

### 6. 常用组合操作

```bash
# 启动 → 查看状态 → 查看日志
bash start.sh && \
  bash status.sh --json && \
  tail -n 50 /sdcard/isgbackup/ha/hass_runtime.log
```

---

> **注意**：`start.sh` 只负责启动服务，不会开启备份或巡检；长期健康监控请使用 `autocheck.sh` 或让安卓 App 定时执行 `autocheckall.sh`。
