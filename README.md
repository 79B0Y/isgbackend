# isgbackend# LinknLink 嵌入式服务全生命周期管理设计说明

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
│ │ /opt/services/      │                                 │
│ │  ├── home_assistant/│ autocheck.sh ▸ monitor.py  …   │
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

### 2.3 目录布局

```
/opt/services/
  <service_id>/
    install.sh      # 初次安装及依赖
    uninstall.sh    # 卸载清理
    start.sh / stop.sh / status.sh
    backup.sh / restore.sh
    update.sh       # 升级执行脚本（读取环境变量 VERSION/TARGET_VERSION，脚本本身不在线更新）
    autocheck.sh    # 健康检查+自愈入口
    VERSION         # 当前脚本包版本（SemVer）
    monitor.py      # MQTT 上报器
  _downloads/       # 临时下载区
  bootstrap_install.sh  # 按服务 id 引导安装脚本包
  autocheckall.sh   # 遍历所有已安装服务
```

---

## 3 云端组件

### 3.1 注册表 `registry.json`

```json
{
  "generated": "2025-07-09T15:00:00Z",
  "services": [
    {
      "id": "home_assistant",
      "display_name": "Home Assistant Core",
      "latest_version": "1.3.2",
      "package_url": "https://dl.linknlink.com/services/ha-scripts-1.3.2.tar.gz",
      "package_sha256": "e4f41c7…"
    }
  ]
}
```

* **新增服务**：向数组追加一段并上传对应 tar 包。
* **删除服务**：从数组移除即可，本地旧目录仍可运行或提示已弃用。

### 3.2 脚本包规范

* 命名：`<id>-scripts-<version>.tar.gz`。
* 解压后直接落在 `/opt/services/<id>/`，必须包含 `VERSION` 文件。

### 3.3 发布与回滚

* CDN/HTTPS 提供；保留最近 ≤5 版本 tar 包，便于回滚。
* 可选：对 `registry.json` 与 tar 包做 GPG 签名。

---

## 4 本地组件

### 4.1 `bootstrap_install.sh`

> 一键安装尚未存在的服务

```bash
bash /opt/services/bootstrap_install.sh ble_gateway
```

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

### 4.4 `monitor.py`

统一的 MQTT 上报器，示例负载：

```json
{
  "service": "home_assistant",
  "status": "running",
  "script_version": "1.3.2",
  "pid": 22104,
  "timestamp": 1720457910
}
```

---

## 5 版本与更新流程

| 步骤      | 动作                                                        |
| ------- | --------------------------------------------------------- |
| ① 比对版本  | `autocheck.sh` → `update.sh` 读取 registry.json 与本地 VERSION |
| ② 下载包   | `curl -L` 保存至 `_downloads/`，校验 SHA‑256                    |
| ③ 备份旧脚本 | 复制到 `release/<oldver>-时间戳`                                |
| ④ 解压覆盖  | `tar -xzf … --strip-components=1`                         |
| ⑤ 上报更新  | `monitor.py` 状态值 `updated`                                |

> **说明：** `update.sh` 逻辑通用且稳定，**不会被在线替换**。若需同时升级“服务二进制（如 npm/pip 包）”，可在新的 `install.sh` 中检测并执行；实际目标版本由环境变量 `TARGET_VERSION`（或 `VERSION_OVERRIDE`）指定。

---

## 6 MQTT 主题映射

| 主题                    | Retain | 说明            |
| --------------------- | ------ | ------------- |
| `isg/status/<id>`     | ✅      | 单服务运行状态 JSON  |
| `isg/status/versions` | ✅      | 所有已安装服务脚本版本汇总 |
| `isg/log/<id>`        | ⬜      | 可选：最近日志片段     |

默认 Broker：`tcp://127.0.0.1:1883`；可通过 `.env` 覆写。

---

## 7 安卓 App 交互

1. **基于密钥的 SSH** 登录 8022。
2. 每 60 s 执行 `bash /opt/services/autocheckall.sh`。
3. MQTT 订阅 → 渲染卡片（状态、版本、内存等）。
4. 提供按钮：

   * 安装新服务：`bootstrap_install.sh <id>`
   * 备份 / 还原 / 手动更新
   * 查看服务日志

---

## 8 安全加固

| 威胁        | 对策                                       |
| --------- | ---------------------------------------- |
| MITM 篡改脚本 | HTTPS + SHA‑256/GPG 校验                   |
| SSH 密码暴力  | 仅允许运行密钥登录；限制用户                           |
| 脚本被修改     | `/opt/services` 700 root\:root；自动校验脚本完整性 |
| 无限重装      | 在 `autocheck.sh` 中记录失败计数与退避时间            |
| 磁盘爆满      | 备份保留数、日志轮转、清理 `_downloads`               |

---

## 9 可靠性特性

* **flock 互斥**：避免并发自检。
* **cron/runit watchdog**：保证 `autocheckall.sh` 自身被定期调用。
* **多级自愈**：`status → start → restore → reinstall → crash`。

---

## 10 新增服务流程

1. 准备完整七脚本 + `VERSION`。
2. 打包成 tar.gz 上传 CDN。
3. 在 registry.json 追加记录。
4. 设备刷新后用户 `bootstrap_install.sh <id>` 即可安装。

---

## 11 词汇表

| 术语    | 说明                                     |
| ----- | -------------------------------------- |
| 服务 ID | registry.json 中的唯一键，如 `home_assistant` |
| 脚本包   | 包含生命周期脚本的压缩档                           |
| 注册表   | 云端 JSON 索引文件                           |
| 自愈    | 服务异常后自动恢复到运行状态                         |

---

**文件结束**
