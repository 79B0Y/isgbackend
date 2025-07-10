## Home Assistant 启动脚本使用说明 (`stop.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/stop.sh`

> **脚本作用**
>
> * 通过启动服务 echo d > $LSVDIR/hass/supervise/control 来停止home assistant
> * 输出启动日志至 `/sdcard/isgbackup/hass/stop<时间>.log`，运行日志至 `hass_stoptime.log`。
> * 启动home assistant运行后，通过status.sh脚本查看服务是否在运行
> * 通过termux Mosquitto cli 上报 MQTT，主题：isg/run/hass/status `stoping` → `stoped` / `failed`。
> * MQTT broker信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml获取

---

### 1. 状态流程

| 阶段       | 说明                       | MQTT 上报                        |
| -------- | ------------------------ | ------------------------------ |
| stoping | 执行停止命令后立即发布              | `{status:"stoping"}`          |
| stoped  | `status.sh` 连续检查成功       | `{status:"stopped"}`           |
| failed   | 启动命令失败或 5 分钟内未达到 stoped | `{status:"failed", error:"…"}` |

---

调用成功示例输出：

```
[INFO] hass 已后台停止，日志写入 /sdcard/isgbackup/hass/hass_stoptime.log
[OK] Home Assistant 已停止
```

---

### 3. 环境变量

| 变量             | 默认值                    | 说明                         |
| -------------- | ---------------------- | -------------------------- |
| `BACKUP_DIR`   | `/sdcard/isgbackup/hass` | 启动 & 运行日志目录                |
| `MAX_TRIES`    | 30 （脚本内变量）             | 轮询次数，间隔 10 秒=5 分钟          |

---

### 4. 日志说明

| 文件                 | 内容                             |
| ------------------ | ------------------------------ |
| `stop_<时间>.log`   | 启动脚本本身输出（包含 MQTT 上报结果）         |
| `hass_stoptime.log` | hass 运行时 `stdout/stderr`（持续写入） |

查看最新运行日志：

```bash
tail -f /sdcard/isgbackup/hass/hass_stoptime.log
```

---

> **注意**：`stop.sh` 只负责停止服务，不会开启备份或巡检；长期健康监控请使用 `autocheck.sh` 或让安卓 App 定时执行 `autocheckall.sh`。
