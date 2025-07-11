## Autocheckall.sh 优化设计

本文是 Termux 环境下自动检查 runit 和 isgservicemonitor 服务运行状态的脚本设计规范，包括 MQTT 状态上报、故障恢复以及服务自动重启。

---

### 1) 确保 runit 正常运行

#### ✅ 步骤

1. **检测 `runsvdir` 是否运行**

   ```bash
   if ! pgrep -f runsvdir >/dev/null; then
       echo "[!] runsvdir 未运行，尝试启动..."
       runsvdir -P /data/data/com.termux/files/usr/etc/service &
       sleep 2
       if pgrep -f runsvdir >/dev/null; then
           runsvdir_status="restarted"
       else
           runsvdir_status="failed"
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

### 2) 确认 runsv 是否监控重要服务

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
  "isgservicemonitor": "run" | "down",
  "sshd": "run" | "down",
  "mysqld": "run" | "down"
}
```

---

### 3) 确保 isgservicemonitor 服务启动和安装

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

### 4) 确认 isgservicemonitor 服务最终状态

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

### ✨ 可选扩展：

* 封装为函数 `check_runit()` `check_isg()` 方便重用
* 实现 MQTT 日志推送函数 `mqtt_report <topic> <payload>`
* 在 `.bashrc` 中加入 runsvdir 自启控制

---






Autocheckall.sh 的职责

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

