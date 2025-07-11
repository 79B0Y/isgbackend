## Autocheckall.sh 优化设计

本文是 Termux 环境下自动检查 runit 和 isgservicemonitor 服务运行状态的脚本设计规范，包括 MQTT 状态上报、故障恢复以及服务自动重启。

---

### ὓ9 1) 确保 runit 正常运行

#### ✅ 步骤

1. **检测 runsvdir 是否运行（避免与 isgservicemonitor 重复启动）**

   ```bash
   if ! pgrep -f runsvdir >/dev/null; then
       if pgrep -f "com.termux.*isgservicemonitor" >/dev/null; then
           echo "[INFO] runsvdir 未运行，但 isgservicemonitor 已在运行，跳过本地启动。"
           runsvdir_status="assumed_by_isgservicemonitor"
       else
           echo "[!] runsvdir 未运行，尝试由 autocheckall.sh 启动..."
           runsvdir -P /data/data/com.termux/files/usr/etc/service &
           sleep 2
           if pgrep -f runsvdir >/dev/null; then
               runsvdir_status="restarted"
           else
               runsvdir_status="failed"
           fi
       fi
   else
       runsvdir_status="running"
   fi
   ```

   【MQTT】 isg/system/runit/status

   ```json
   { "runsvdir": "running" | "restarted" | "failed" }
   ```

2. **检查服务目录是否配置正确**

   ```bash
   service_dir="/data/data/com.termux/files/usr/etc/service"
   missing_services=()
   for d in "$service_dir"/*; do
       if [ -d "$d" ]; then
           if [ ! -x "$d/run" ]; then
               chmod +x "$d/run"
               missing_services+=("$(basename "$d")")
           fi
       fi
   done
   service_valid=true
   if [ ${#missing_services[@]} -gt 0 ]; then
       service_valid=false
   fi
   ```

   【MQTT】 isg/system/runit/service\_dir

   ```json
   { "valid": true | false, "missing_services": ["xxx"] }
   ```

3. **启动失败处理建议：**

   * 若 runsvdir 启动失败，检查 Termux 权限、是否缺少依赖（如 `runit` 未安装）。
   * 可重装：

     ```bash
     pkg install runit -y
     ```
   * 若服务目录无效：尝试重新初始化服务结构或回滚最近变更。

---

### ὓ9 2) 确认 runsv 是否监控重要服务

#### ✅ 目标服务：

* isgservicemonitor
* sshd
* mysqld

#### 检查方法

```bash
sv status isgservicemonitor
sv status sshd
sv status mysqld
```

【MQTT】 isg/system/runit/supervision

```json
{
  "isgservicemonitor": "run" | "down" | "invalid",
  "sshd": "run" | "down" | "invalid",
  "mysqld": "run" | "down" | "invalid"
}
```

---

### ὓ9 3) 确保 isgservicemonitor 服务启动和安装

#### ✅ 步骤

1. **检查是否运行**

```bash
pgrep -f "com.termux.*isgservicemonitor" >/dev/null
```

2. **若未启动，试回 3 次**

```bash
for i in {1..3}; do
    sv start isgservicemonitor
    sleep 5
    pgrep -f "com.termux.*isgservicemonitor" >/dev/null && break
done
```

【MQTT】 isg/system/isgservicemonitor/start

```json
{ "status": "failed", "attempts": 3 }
```

3. **检查 isgservicemonitor 是否安装**

```bash
test -f /data/data/com.termux/files/usr/var/termuxservice/isgservicemonitor/isgservicemonitor
```

4. **若未安装，执行下列操作：**

```bash
rm -f isgservicemonitor_latest_termux_arm.deb
wget --no-check-certificate https://eucfg.linklinkiot.com/isg/isgservicemonitor_latest_termux_arm.deb
sv stop isgservicemonitor
rm -rf /data/data/com.termux/files/usr/var/termuxservice/isgservicemonitor
pkill -f "isgservicemonitor"
sleep 5
dpkg -i isgservicemonitor_latest_termux_arm.deb
sleep 5
```

5. **重试启动 3 次**

```bash
for i in {1..3}; do
    sv start isgservicemonitor
    sleep 5
    pgrep -f "com.termux.*isgservicemonitor" >/dev/null && break
done
```

【MQTT】 isg/system/isgservicemonitor/install

```json
{ "status": "failed", "reinstall_attempted": true }
```

---

### ὓ9 4) 确认 isgservicemonitor 服务最终状态

```bash
sv status isgservicemonitor
```

【MQTT】 isg/system/isgservicemonitor/final\_status

```json
{
  "status": "running" | "stopped",
  "pid": 1234,
  "uptime": "120s"
}
```

---

### ὓ9 5) 各服务子系统可用性自检（并赋予权限）

在 isgservicemonitor 成功启动后，自动调用各个服务的自检脚本，以验证其独立可用性：

#### ✅ 检查流程：

0. **为所有 autocheck.sh 赋可执行权限**：

```bash
find /data/data/com.termux/files/home/servicemanager -type f -name 'autocheck.sh' -exec chmod +x {} \;
```

1. 遍历服务子系统目录（例如 servicemanager 下的各模块）：

```bash
for service in /data/data/com.termux/files/usr/servicemanager/*; do
    [ -f "$service/autocheck.sh" ] && bash "$service/autocheck.sh"
    # 建议每个 autocheck.sh 内部自行处理 MQTT 上报
done
```

2. 每个 `<service_id>/autocheck.sh` 自检脚本应实现：

   * 启动状态验证（端口/进程/功能）
   * 输出标准 MQTT 上报，如：

     ```json
     isg/service/<service_id>/status {
       "status": "ok" | "failed",
       "detail": "port open, mqtt connected..."
     }
     ```

3. 示例目录结构：

```
servicemanager/
├── hass/
│   └── autocheck.sh
├── mosquitto/
│   └── autocheck.sh
└── z2m/
    └── autocheck.sh
```

4. 建议统一封装 MQTT 上报工具函数 `mqtt_report <topic> <json_payload>` 供所有 autocheck.sh 使用。

---

### ✨ 通用优化建议

#### ✅ 日志输出函数

```bash
log_info()  { echo "[INFO] $1"; }
log_warn()  { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }
```

建议全程用 `log_info` 等替代 echo，提高一致性与可调试性。

#### ✅ MQTT 上报函数

```bash
mqtt_report() {
  local topic="$1"
  local payload="$2"
  mosquitto_pub -h "$MQTT_HOST" -p "$MQTT_PORT" -t "$topic" -m "$payload"
}
```

* 从 `configuration.yaml` 提取 `$MQTT_HOST`、`$MQTT_PORT`，建议集中读取一次。

#### ✅ 路径与环境变量统一

```bash
SERVICEMANAGER_DIR="${SERVICEMANAGER_DIR:-/data/data/com.termux/files/home/servicemanager}"
```

用于替代文中硬编码路径。

#### ✅ 加入并发锁防护

```bash
(
  flock -n 200 || {
    echo "[WARN] 检测到已有 autocheckall.sh 实例运行，退出"
    exit 1
  }

  # ⬇️ 脚本主体放在这里
  bash autocheck_core.sh

) 200>/data/data/com.termux/files/usr/var/lock/autocheckall.lock
```

防止多个任务（cron / App）同时触发造成冲突。

#### ✅ 支持服务黑名单（跳过某些服务）

```bash
IFS=',' read -r -a SKIP <<< "${SKIP_SERVICES}"
[[ " ${SKIP[*]} " =~ " $sid " ]] && continue
```

环境变量 `SKIP_SERVICES=hass,mysqld` 可跳过指定服务。

#### ✅ 汇总统一上报版本和状态（可选）

```json
isg/status/versions {
  "timestamp": 1720575012,
  "services": {
    "hass": { "version": "1.3.2", "status": "running" },
    "z2m": { "version": "1.1.0", "status": "failed" }
  }
}
```

通过汇总每个服务 autocheck 输出生成。

---

### ✨ 可选扩展：

* 封装为函数 `check_runit()` `check_isg()` 方便重用
* 实现 MQTT 日志推送函数 `mqtt_report <topic> <payload>`
* 在 `.bashrc` 中加入 runsvdir 自启控制

---

### 📡 MQTT 上报主题汇总

#### 🧩 runit 系统相关

* `isg/system/runit/status`

  ```json
  { "runsvdir": "running" | "restarted" | "failed" }
  ```
* `isg/system/runit/service_dir`

  ```json
  { "valid": true | false, "missing_services": ["xxx"] }
  ```
* `isg/system/runit/supervision`

  ```json
  {
    "isgservicemonitor": "run" | "down",
    "sshd": "run" | "down",
    "mysqld": "run" | "down"
  }
  ```

#### 🛡️ isgservicemonitor 服务相关

* `isg/system/isgservicemonitor/start`

  ```json
  { "status": "failed", "attempts": 3 }
  ```
* `isg/system/isgservicemonitor/install`

  ```json
  { "status": "failed", "reinstall_attempted": true }
  ```
* `isg/system/isgservicemonitor/final_status`

  ```json
  {
    "status": "running" | "stopped",
    "pid": 1234,
    "uptime": "120s"
  }
  ```

#### 🧪 各服务自检（来自 `autocheck.sh`）

* `isg/service/<service_id>/status`

  ```json
  {
    "status": "ok" | "failed",
    "detail": "port open, mqtt connected..."
  }
  ```

#### 📦 版本汇总上报

* `isg/status/versions`

  ```json
  {
    "timestamp": 1720575012,
    "services": {
      "hass": { "version": "1.3.2", "status": "running" },
      "z2m": { "version": "1.1.0", "status": "failed" }
    }
  }
  ```

---




Autocheckall.sh 的职责提示词

1） 确保runit正常运行 
    - ps aux | grep runsvdir，MQTT 上报结果
    - 检查服务目录是否正确配置，/data/data/com.termux/files/usr/etc/service/，MQTT 上报结果
    🔍 没有 runsvdir → 手动运行 runsvdir
                   ↓
    🔧 服务目录结构错误 → 修复目录 & 权限 & run 脚本
                   ↓
    🔧 run 脚本写法问题 → 检查 exec 命令是否正确
                   ↓
    🧪 日志调试 → 输出日志到文件，tail 分析
                   ↓
    ✅ 一切正常后可添加自启动逻辑

2） ps aux | grep runsv，确认isgservicemonitor，sshd，mysqld正常被监管,MQTT 上报结果
  
3）isgservicemonitor用runit来启动和保护，确保isgservicemonitor能正确启动
  - 通过检查isgservicemonitor的进程，来确认是否在运行 pgrep -f "com.termux.*isgservicemonitor" >/dev/null && echo yes || echo no
  - 没有运行，用 sv start isgservicemonitor 启动，尝试3次，没有成功启动，MQTT 上报
  - 检查isgservicemonitor服务是否正确安装，/data/data/com.termux/files/usr/var/termuxservice/isgservicemonitor/isgservicemonitor 是否存在
  - 不存在，执行安装
     rm -f isgservicemonitor_latest_termux_arm.deb
     wget --no-check-certificate https://eucfg.linklinkiot.com/isg/isgservicemonitor_latest_termux_arm.deb
     sv stop isgservicemonitor
     rm -rf  /data/data/com.termux/files/usr/var/termuxservice/isgservicemonitor 
     pkill -f "isgservicemonitor"
     sleep 5
     dpkg -i isgservicemonitor_latest_termux_arm.deb
     sleep 5
     sv restart isgservicemonitor
  - 安装后再次用 sv start isgservicemonitor 启动，尝试3次，没有成功启动，MQTT 上报

4) isgservicemonitor服务是启动状态，sv status isgservicemonitor

5）当确保了isgservicemonitor服务启动之后，分别使用各个服务<service_id>里的autocheck来检查其可用性，例如 servicemanager/hass/autocheck.sh, 检查后将结果用MQTT上报

6）由于 isgservicemonitor ，做了与runit相互保全的工作，isgservicemonitor 也会每隔一段时间检查 rundir有没有起来，为了避免重复启用runit，在确保 runit 正常运行里，启动runsvdir -P /data/data/com.termux/files/usr/etc/service &之前需要提前判断 isgservicemonitor是否在运行

7）把autocheckall里涉及到所有的mqtt消息汇总一下，放在文档最后面
8）在 sv status 的 MQTT 上报中加入了 "invalid" 状态，用于表示 runsv not running 等异常情况，避免误判为正常或仅是未启动。

