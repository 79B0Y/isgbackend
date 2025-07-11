## Home Assistant 自检脚本使用说明 (`autocheck.sh`)

> 脚本路径
> `/data/data/com.termux/files/home/servicemanager/hass/autocheck.sh`

---

### 功能概览

* 【一键自愈】自动检测 Home Assistant 是否运行并自动尝试修复
* 【并可重复】支持 cron / runit / Android App 马路调用，不会导致异常
* 【参数化配置】连续启动失败间隔、自动更新时间规则等可通过环境变量控制
* 【MQTT上报】支持 running / recovered / failed / permanent\_failed / disabled / config 等多种状态上报，便于前端控制和监控
* 【配置文件】MQTT broker 信息从 `configuration.yaml`获取
* 【错误自恢复】如果未运行且未 disable，则自动调用 start.sh，失败 3 次后调用 install.sh + restore.sh 重装

---

### 执行逻辑

| 阶段 | 操作说明                                                                                                                                                | MQTT 状态                                          |
| -- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| 0  | 取环境变量 AC\_MAX\_FAILS / AC\_UPDATE\_INTERVAL，立即上报 config                                                                                             | `config`                                         |
| 1  | 检测 `.disabled`；存在则上报 `disabled`，立即退出                                                                                                                | `disabled`                                       |
| 2  | 检测 `VERSION`；缺失则执行 `install.sh`                                                                                                                     | 由 install.sh 上报 installed / failed               |
| 3  | 检测配置目录是否完整；缺失则执行 `restore.sh`                                                                                                                       | restore\_success / failed                        |
| 4  | 检测 Home Assistant 运行状态<br>   - running 则上报 `running`<br>   - 未运行则调用 start.sh<br>   └ 成功则上报 `recovered`<br>   └ 失败则增加失败计数，超过阈值则上报 `permanent_failed` | running / recovered / failed / permanent\_failed |
| 5  | 如果距离上次更新超过 AC\_UPDATE\_INTERVAL 且存在 TARGET\_VERSION，则执行 `update.sh`                                                                                 | update\_success / failed                         |

---

### 环境变量

| 名称                   | 默认值                      | 说明                           |
| -------------------- | ------------------------ | ---------------------------- |
| `PROOT_DISTRO`       | `ubuntu`                 | 容器名称                         |
| `BACKUP_DIR`         | `/sdcard/isgbackup/hass` | 日志与备份目录                      |
| `AC_MAX_FAILS`       | `3`                      | 连续失败超过阈值则转 permanent\_failed |
| `AC_UPDATE_INTERVAL` | `21600` (即 6 小时)         | 最小更新间隔时间                     |
| `TARGET_VERSION`     | *(空)*                    | 指定更新目标版本                     |

---

### 日志 & 并发防护

* 日志文件：写入 `$BACKUP_DIR/autocheck_<timestamp>.log`
* 并发锁：`/var/lock/ha_autocheck.lock`，如果存在则直接退出

---

### 配合脚本执行顺序

1. `status.sh`：判断 Home Assistant 是否运行
2. `.disabled`：如果存在则直接结束，MQTT 上报 `disabled`
3. 如果未运行，调用 `start.sh`，自动重试 3 次
4. 如果失败，执行 `install.sh`，重装 Home Assistant
5. 执行 `restore.sh`，还原最新或默认备份
6. 再次执行 `start.sh`，確保服务运行

---

> 推荐 Android App 订阅 MQTT 为: `isg/autocheck/home_assistant/status` ，方便实时监控
> 如需统一检查请调用 `autocheckall.sh`
> 如一次性备份，请使用 `backup.sh`；如需还原请使用 `restore.sh`


## 服务看护脚本包各脚本的职责说明

本段描述通用于 Termux + Proot Ubuntu 环境下的服务脚本包，为后续自检、维护、可观化等操作打基础。

### 基础脚本职责

1. **`status.sh`**

   * 探測服务是否正常运行（进程、端口、运行时长）
   * 输出 `running` / `starting` / `stopped`
   * 通过 MQTT 上报详细状态

2. **`start.sh`**

   * 启动服务，移除 `.disabled` 标志
   * 调用 `status.sh` 确认启动成功
   * 上报 `starting` 到 `running` 或 `failed` 的 MQTT 状态

3. **`stop.sh`**

   * 停止服务，创建 `.disabled` 标志
   * 调用 `status.sh` 确认已停止
   * 上报 `stoping` 到 `stopped` 或 `failed` 的 MQTT 状态

4. **`install.sh`**

   * 在 Proot 容器中安装指定版本服务，初始化环境
   * 调用 `start.sh` 验证服务启动是否成功
   * 通过 MQTT 上报 `installing` 到 `installed` / `failed`

5. **`update.sh`**

   * 使用 pip 升/降级 Home Assistant 到指定版本
   * 更新后重启服务确认正常运行
   * 上报 `updating` 到 `success` / `failed`

6. **`uninstall.sh`**

   * 调用 `stop.sh`，删除 Python 虚拟环境和配置文件
   * 创建 `.disabled`，防止 autocheck 重装
   * 上报 `uninstalling` 到 `uninstalled` / `failed`

7. **`backup.sh`**

   * 将 Home Assistant 配置文件压缩备份
   * 运行前检测服务必须处于 running 状态
   * 上报 `backuping` 到 `success` / `failed`

8. **`restore.sh`**

   * 选择最新或指定备份文件进行还原
   * 还原前停止服务，还原后重启
   * 上报 `restoring` 到 `success` / `failed`

9. **`VERSION.yaml`**

   * 记录当前脚本包版本和变更日志

---

### 日志管理

* 所有脚本日志写入:
  `/data/data/com.termux/files/home/servicemanager/<service_id>/logs/<script>.log`
* 日志最多保留 500 条，超出自动删除旧日志

---

> 如无意外，上述脚本应包含于每个服务脚本包里，用于支持自检/备份/升级/重装等完整生命周期管理。
















## Home Assistant 自检脚本使用说明 (`autocheck.sh`)提示词

> **脚本路径**
> `/data/data/com.termux/files/home/servicemanager/hass/autocheck.sh`

> **脚本概览**
>
> * **一键自愈**：自动安装、修复、启动并定期更新 Home Assistant。
> * **幂等设计**：可被 cron/runit/Android App 频繁调用，无并发风险。
> * **参数化**：失败阈值与版本检查间隔全部通过环境变量配置。
> * **MQTT**：实时上报 `running / recovered / failed / permanent_failed / disabled / config` 等状态，供前端可视化。
> * MQTT broker信息从 /data/data/com.termux/files/home/servicemanager/configuration.yaml获取
> * 如果状态不是running, 没有disable标志，先尝试启动homesistant，尝试3次都无法启动，尝试安装home assistant


> **服务下各个脚本的职责**
1) status.sh：查询服务的当前运行状态，最后显示running / stop，mqtt上报
2) start.sh: 负责启动服务，并去掉disable标志，mqtt上报服务启动的过程和结果，并通过status查询结果，mqtt上报
3) stop.sh: 负责停止服务，并给出disable标志，mqtt上报服务停止的过程和结果，并通过status查询结果，mqtt上报
4）install.sh：负责通过cli指令安装服务指定版本，mqtt上报服务安装的过程和结果，使用start脚本，测试服务安装是否ok，
5）update.sh：负责通过cli指令升级服务指定版本，mqtt上报服务升级的过程和结果，使用start脚本，测试服务安装是否ok
6）uninstall.sh: 负责卸载服务，先使用stop脚本停止，然后删除服务。mqtt上报服务卸载的过程和结果
7）backup.sh: 负责备份该服务的数据，mqtt上报服务备份的过程和结果
8）restore.sh: 负责还原该服务的数据，mqtt上报服务还原的过程和结果
9）VERSION.yaml: 记录改服务脚本包的版本和历史修改
所有脚本生成的log都在 /data/data/com.termux/files/home/servicemanager/<service_id>/logs/脚本名称.log，保留最近的500条。


### 2. 运行逻辑

1) 通过status.sh来判断home assistant是否正常运行
2) 没有运行，检查.disable标志，如果有.disable则skip，MQTT 上报
3) 没有.disable标志，也没正常运行，尝试使用start.sh来启动，重试3次
6) 没有成功启动，使用install.sh重新安装一次home assistant，MQTT 上报
7) 使用restore.sh来还原默认备份，或者backup.sh产生的备份
9) 使用start.sh来启动home assistant

最终目的是为了保证home assistant能够成功启动
