## Home Assistant 自检脚本使用说明 (`autocheck.sh`)

> **脚本路径**
> `/data/data/com.termux/files/home/services/home_assistant/autocheck.sh`

> **脚本概览**
>
> * **一键自愈**：自动安装、修复、启动并定期更新 Home Assistant。
> * **幂等设计**：可被 cron/runit/Android App 频繁调用，无并发风险。
> * **参数化**：失败阈值与版本检查间隔全部通过环境变量配置。
> * **MQTT**：实时上报 `running / recovered / failed / permanent_failed / disabled / config` 等状态，供前端可视化。

---

### 1. 快速调用

```bash
# 默认参数
bash autocheck.sh

# 自定义：失败阈值 5 次，版本检查间隔 3 小时
AC_MAX_FAILS=5 AC_UPDATE_INTERVAL=$((3*3600)) bash autocheck.sh
```

---

### 2. 运行逻辑

| 阶段 | 动作                                                                                                                             | 上报状态                              |
| -- | ------------------------------------------------------------------------------------------------------------------------------ | --------------------------------- |
| 0  | **参数上报**：读取 `AC_MAX_FAILS` / `AC_UPDATE_INTERVAL` 并立即上报                                                                        | `config`                          |
| 1  | 检测 `.disabled`                                                                                                                 | `disabled`（跳过余下流程）                |
| 2  | 检测脚本是否安装（`VERSION`）缺失则 `install.sh`                                                                                            | `install_success / failed` 由子脚本上报 |
| 3  | 配置目录不在则 `restore.sh`                                                                                                           | `restore_success / failed`        |
| 4  | 运行状态：<br>• running → `running`<br>• 非运行 → `start.sh`<br>    ↳ 成功 → `recovered`<br>    ↳ 失败计数累加 → `failed` 或 `permanent_failed` |                                   |
| 5  | 距上次更新 ≥ `AC_UPDATE_INTERVAL` 且 `TARGET_VERSION` 已定义 → `update.sh`                                                              | `update_success / failed`         |

---

### 3. 主要环境变量

| 变量                   | 默认值                    | 说明                                |
| -------------------- | ---------------------- | --------------------------------- |
| `PROOT_DISTRO`       | `ubuntu`               | 容器名称 (proot-distro list)          |
| `BACKUP_DIR`         | `/sdcard/isgbackup/ha` | 日志与备份根目录                          |
| `AC_MAX_FAILS`       | `3`                    | 连续启动失败计数阈值；达到即 `permanent_failed` |
| `AC_UPDATE_INTERVAL` | `21600` (6h)           | 与上次 `update.sh` 间隔秒数              |
| `TARGET_VERSION`     | *(空)*                  | 设定后启用自动版本更新                       |

---

### 4. 日志与锁

* **日志文件**：`autocheck_<timestamp>.log` 写入 `BACKUP_DIR`。
* **并发锁**：`/var/lock/ha_autocheck.lock`，第二个实例会检测到并立即退出。

---

### 5. 用于定时任务示例

**Termux runit**

```bash
# /data/data/com.termux/files/usr/var/service/ha-autocheck/run
#!/data/data/com.termux/files/usr/bin/bash
exec every 60 /data/data/com.termux/files/home/services/home_assistant/autocheck.sh
```

**crontab (容器内)**

```cron
* * * * *  bash /services/home_assistant/autocheck.sh
* * * * *  sleep 30 && bash /services/home_assistant/autocheck.sh
```

---

### 6. 故障排查

| MQTT 状态            | 可能原因                                 | 处理建议                           |
| ------------------ | ------------------------------------ | ------------------------------ |
| `failed`           | `start.sh` 启动未成功，查看 `fail.count` 与日志 | 检查依赖 / 端口占用                    |
| `permanent_failed` | 达到 `AC_MAX_FAILS`                    | 手动执行 `start.sh` 观察详细错误         |
| `disabled`         | 用户执行了 `stop.sh` 并未重新启动               | 运行 `start.sh` 或删除 `.disabled`  |
| 更新不触发              | `TARGET_VERSION` 未定义或间隔未到            | 设置环境变量并等待 `AC_UPDATE_INTERVAL` |

---

> **提示**
>
> * 建议让 Android App 订阅 `isg/status/home_assistant` 来实时显示状态。
> * 修改阈值或间隔后，下一次运行即可生效并上报新的 `config` 信息。
