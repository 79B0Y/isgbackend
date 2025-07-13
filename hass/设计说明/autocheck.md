## `autocheck.sh` 自检脚本设计说明

📂 路径：`/data/data/com.termux/files/home/servicemanager/hass/autocheck.sh`

---

### 一、设计目标

| 目标           | 说明                                        |
| ------------ | ----------------------------------------- |
| ✅ 自愈能力       | 自动检测 Home Assistant 状态并修复异常，确保服务持续运行      |
| 🔁 可重复调用     | 可被 cron / runit / Android App 多次触发，幂等无副作用 |
| ⚙️ 参数化配置     | 支持通过环境变量配置失败阈值与更新间隔，适配不同场景                |
| 📡 MQTT 可观测性 | 全流程状态通过 MQTT 实时上报，包括运行状态、性能指标、失败原因等       |
| 🔐 安全与互斥     | 支持 flock 并发锁机制，防止并行执行造成冲突                 |

---

### 二、功能流程

| 阶段 | 操作说明                                                                   | MQTT 状态主题                                               |
| -- | ---------------------------------------------------------------------- | ------------------------------------------------------- |
| 0  | 加载配置、创建日志目录，写入锁文件 `.lock_autocheck`                                    | `isg/autocheck/hass/status` → `config`                  |
| 1  | 检查 `.disabled` 存在：跳过后续流程，退出                                            | `disabled`                                              |
| 2  | 检查 `VERSION.yaml` 是否存在；不存在则执行 `install.sh`                             | 安装失败上报 `failed`                                         |
| 3  | 检查必要脚本与目录是否存在（如 `start.sh`），否则执行 `restore.sh` 恢复                       | 恢复失败上报 `failed`                                         |
| 4  | 执行 `status.sh` 检查服务是否运行：                                               | `running` / `recovered` / `failed` / `permanent_failed` |
|    | - 若未运行，尝试最多重启 3 次，记录失败次数（`.failcount`）                                 |                                                         |
|    | - 若超出失败阈值（默认 3 次），自动执行 `install.sh + restore.sh + start.sh` 作为强自愈流程    |                                                         |
| 5  | 收集运行性能（PID/CPU/MEM/运行时间），通过 MQTT 上报性能状态                                | `isg/status/hass/performance`                           |
| 6  | 检查是否达到升级间隔 `AC_UPDATE_INTERVAL`（默认 6 小时）且指定了 `TARGET_VERSION`；如满足则执行更新 | `update.sh` → `success` / `failed`                      |
| 7  | 执行完成，清理锁，记录日志                                                          | —                                                       |

---

### 三、核心能力说明

#### ✅ 状态检测逻辑

调用 `status.sh` 判断服务是否 `running`，判断依据包括 PID 是否存在 + TCP 8123 端口是否监听。

#### 🔄 启动与恢复

若服务未运行：

1. 调用 `start.sh` 尝试启动（最多重试 3 次）
2. 启动失败次数超限后，执行强自愈逻辑：

   * `install.sh`：重新部署脚本与环境
   * `restore.sh`：还原最近配置
   * `start.sh`：再次启动服务

#### 🧠 性能上报

通过 `top` + `/proc/$pid/status` 采集以下运行数据：

* CPU 使用率 %
* 内存使用率 %
* RSS 实际驻留内存 KB
* 运行时长
  统一通过主题：`isg/status/hass/performance` 上报 JSON 格式数据。

#### ⬆️ 自动更新

若配置 `TARGET_VERSION` 且时间间隔超过 `AC_UPDATE_INTERVAL`（单位秒），自动调用 `update.sh` 升级到指定版本。

---

### 四、环境变量支持

| 名称                   | 默认值                      | 说明                       |
| -------------------- | ------------------------ | ------------------------ |
| `PROOT_DISTRO`       | `ubuntu`                 | 容器名称                     |
| `BACKUP_DIR`         | `/sdcard/isgbackup/hass` | 日志与备份目录                  |
| `AC_MAX_FAILS`       | `3`                      | 启动失败次数阈值，超过后执行 reinstall |
| `AC_UPDATE_INTERVAL` | `21600`（6 小时）            | 最小自动更新间隔（秒）              |
| `TARGET_VERSION`     | *(空)*                    | 指定目标版本，触发 `update.sh` 使用 |

---

### 五、日志管理与并发控制

* 日志输出：`$SERVICE_DIR/logs/autocheck_<timestamp>.log`
* 最多保留 500 条日志（通过日志轮转策略控制）
* 并发互斥：使用 `flock` 写入 `.lock_autocheck`，确保自检任务不重入

---

### 六、MQTT 状态主题一览

| 类型      | 主题                                                   | 说明                       |
| ------- | ---------------------------------------------------- | ------------------------ |
| 状态变更    | `isg/autocheck/hass/status`                          | 自检主状态（如 failed, running） |
| 性能上报    | `isg/status/hass/performance`                        | JSON 格式系统性能状态            |
| 安装状态    | `isg/install/hass/status`                            | 安装过程中的阶段与结果              |
| 更新状态    | `isg/update/hass/status` 及子主题                        | 升级过程各阶段进度与失败日志           |
| 启停状态    | `isg/run/hass/status`                                | 启动与停止过程中的状态              |
| 还原/备份状态 | `isg/restore/hass/status` / `isg/backup/hass/status` | 还原与备份任务状态                |

---

### 七、推荐配合脚本

* `autocheckall.sh`：批量调度所有服务自检，推荐每 30 秒运行
* `install.sh / update.sh / restore.sh / start.sh / status.sh`：分别用于服务生命周期中的不同阶段
* `configuration.yaml`：集中管理 MQTT 配置

---

### 八、最佳实践建议

| 操作时机    | 建议调用                                               |
| ------- | -------------------------------------------------- |
| 开机自启动   | runit 或 Android App 调用 `autocheck.sh`              |
| 崩溃恢复    | autocheck 自动完成，记录日志并重试                             |
| 升级窗口    | 设置 `TARGET_VERSION`，由 autocheck 控制更新               |
| 手动排查问题  | 查看日志：`logs/autocheck_*.log`                        |
| 状态可视化集成 | 订阅 `isg/autocheck/hass/status` / `performance` 等主题 |
