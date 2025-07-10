# LinknLink 嵌入式服务全生命周期管理设计说明

## 1 概述

### 1.1 目标

* **持续、自愈运行**：确保所有运行在 Termux + Proot Ubuntu（安卓 Root 设备）中的后台服务（Home Assistant、Zigbee2MQTT、Z‑Wave JS UI 等）始终保持可用，发生异常可自动恢复。
* **统一生命周期工具箱**：为现有及未来的每个服务提供相同的安装 → 运行 → 监控 → 备份 → 更新 → 回滚 → 卸载流程脚本。
* **状态与版本可观测**：通过 MQTT 实时上报服务状态、脚本版本，方便安卓控制端和 Web Dashboard 直观呈现。
* **云端持续交付**：服务脚本包在云端注册表发布后，终端自动发现、下载、升级，无需人为干预。

### 1.2 范围

本说明涵盖脚本结构、云端注册表格式、版本更新逻辑、安全加固方案、安卓交互模式。不包含服务本身的业务功能细节。

---

## 2 系统总体架构

```
┌───────────────┐   HTTPS   ┌─────────────────────────┐
│  云端 CDN      │ registry │  安卓控制 App           │
│  + tar 包      │──────────▶  • 每 60 s SSH 调度      │
└───────────────┘           │  • MQTT 订阅            │
       ▲                    └──────────▲─────────────┘
       │                             MQTT
       │                    (status / versions / logs)
       │                             ▼
┌────────────────────────────────────────────────────────────┐
│   Rooted Android ▸ Termux ▸ Proot Ubuntu (Linux FS)       │
│ ┌──────────────────────┐                                 │
│ │ /data/data/com.termux/files/home/servicemanager/      │                                 │
│ │  ├── hass/│ autocheck.sh   …   │
│ │  ├── zigbee2mqtt/   │                                 │
│ │  ├── zwave_js_ui/   │                                 │
│ │  ├── ble_gateway/…  │                                 │
│ │  └── autocheckall.sh│ cron/runit 每 30 s 执行        │
│ └──────────────────────┘                                 │
└────────────────────────────────────────────────────────────┘
```

### 2.1 运行环境

* **Termux**：提供 Android 用户空间与 OpenSSH（端口 8022）。
* **Proot‑Ubuntu**：完整 glibc Linux 文件系统，所有服务及守护脚本在此运行。

### 2.2 服务定义

服务 = 任何需要长期运行及健康监控的进程，例如 Home Assistant、BLE Gateway。

#### 2.2.1 service\_id 命名规范

* **全小写**，仅使用字母、数字和下划线 (`[a-z0-9_]+`)。
* **必须以字母开头**，避免与数字目录混淆。
* **语义清晰**：能直观反映服务名称或功能（如 `hass`、`zigbee2mqtt`）。
* **全局唯一**：在同一注册表文件 `registry.json` 中不得重复。
* **稳定不变**：一旦发布，不因版本升级而修改；目录名、MQTT 主题、备份路径等均依赖该 ID。
* **文件系统安全**：不含空格、特殊字符，长度 ≤ 32 字符。

> **注意**：`service_id` 会直接用作以下位置：
>
> 1. 本地目录 `/data/data/com.termux/files/home/servicemanager/<service_id>/`
> 2. MQTT 主题:
     服务状态：isg/status/<service_id>/status
     安装与卸载：isg/install/<service_id>/status
     备份：isg/backup/<service_id>/status
     还原：isg/restore/<service_id>/status
     启停：isg/run/<service_id>/status
     升级：isg/update/<service_id>/status
     检查：isg/autocheck/<service_id>/status

### 2.3 目录布局

```
/data/data/com.termux/files/home/servicemanager/
  <service_id>/
    install.sh      # 初次安装及依赖
    uninstall.sh    # 卸载清理
    start.sh / stop.sh / status.sh
    backup.sh / restore.sh
    update.sh       # 升级执行脚本（读取环境变量 VERSION/TARGET_VERSION，脚本本身不在线更新）
    autocheck.sh    # 健康检查+自愈入口
    VERSION         # 当前脚本包版本（SemVer）
  _downloads/       # 临时下载区
  autocheckall.sh   # 遍历所有已安装服务
  configuration.yaml # 配置和更新isg MQTT broker 信息，还有其它配置信息
  serviceupdate.sh  # 去云端拉去最新的servicelist.json,
```

---

## 3 云端组件

### 3.1 注册表 `registry.json`
云端维护一个服务列表，JSON格式
```json
{
  "generated": "2025-07-09T15:00:00Z",
  "services": [
    {
      "id": "home_assistant",
      "display_name": "Home Assistant Core",
      "latest_version": "1.3.2",
      "package_url": "https://dl.linknlink.com/services/hass-scripts-1.3.2.tar.gz",
      "package_sha256": "e4f41c7…"
    }
  ]
}
```
iSG应用程序定期执行/sdcard/isgbackup/servicelist/serviceupdate.sh，

serviceupdate.sh功能
下载将文件保存在 /sdcard/isgbackup/servicelist/servicelist.json 
下载独立服务包保存在 /sdcard/isgbackup/servicelist/hass-scripts-1.3.2.tar.gz
解压服务包到对应的目录下

* **新增服务**：向数组追加一段并上传对应 tar 包。
* **删除服务**：从数组移除即可，本地旧目录仍可运行或提示已弃用。

### 3.2 脚本包规范

* 命名：`<service_id>-scripts-<version>.tar.gz`。
* 解压后直接落在 `/data/data/com.termux/files/home/servicemanager/<service_id>/`，必须包含 `VERSION` 文件。


### 3.3 发布与回滚

* CDN/HTTPS 提供；保留最近 ≤5 版本 tar 包，便于回滚。
* 可选：对 `registry.json` 与 tar 包做 GPG 签名。

---

## 4 本地组件

工作流程：读注册表 → 下载 → 校验 SHA‑256 → 解压 → 写 VERSION → 执行 `install.sh`。

### 4.2 `autocheck.sh`（单服务）

1. 检查已安装；缺失则 `install.sh`。
2. 检查配置完整；缺失则 `restore.sh`。
3. 检查进程；未运行则 `start.sh`。
4. 启动失败计数 ≥3 次 → `reinstall.sh`。
5. 每 6 小时根据环境变量或远端版本信息调用 `update.sh` 执行升级（`update.sh` 脚本本身保持不变）。
6. 调用 `monitor.py` 上报状态。

### 4.3 `autocheckall.sh`（全局）

1. 拉取最新 `registry.json`。
2. 扫描本地 `*/VERSION` 识别已安装服务。
3. 对每个已安装服务 `bash autocheck.sh`（内部带 `flock` 互斥）。
4. 汇总版本并发布到 `isg/status/versions`。

---

## 5 版本与更新流程

| 步骤      | 动作                                                        |
| ------- | --------------------------------------------------------- |
| ① 比对版本  | `autocheck.sh` → `update.sh` 读取 registry.json 与本地 VERSION |
| ② 下载包   | `curl -L` 保存至 `_downloads/`，校验 SHA‑256                    |
| ③ 备份旧脚本 | 复制到 `release/<oldver>-时间戳`                                |
| ④ 解压覆盖  | `tar -xzf … --strip-components=1`                         |
> **说明：** `update.sh` 逻辑通用且稳定，**不会被在线替换**。若需同时升级“服务二进制（如 npm/pip 包）”，可在新的 `install.sh` 中检测并执行；实际目标版本由环境变量 `TARGET_VERSION`（或 `VERSION_OVERRIDE`）指定。

---

## 6 安全加固

| 威胁        | 对策                                       |
| --------- | ---------------------------------------- |
| MITM 篡改脚本 | HTTPS + SHA‑256/GPG 校验                   |
| SSH 密码暴力  | 仅允许运行密钥登录；限制用户                           |
| 脚本被修改     | `/opt/services` 700 root\:root；自动校验脚本完整性 |
| 无限重装      | 在 `autocheck.sh` 中记录失败计数与退避时间            |
| 磁盘爆满      | 备份保留数、日志轮转、清理 `_downloads`               |

---

## 7 可靠性特性

* **flock 互斥**：避免并发自检。
* **cron/runit watchdog**：保证 `autocheckall.sh` 自身被定期调用。
* **多级自愈**：`status → start → restore → reinstall → crash`。

---

## 8 新增服务流程

1. 准备完整七脚本 + `VERSION`。
2. 打包成 tar.gz 上传 CDN。
3. 在 registry.json 追加记录。

---
**文件结束**
