## `VERSION.yaml` 文件设计规范

`VERSION.yaml` 是每个服务脚本包必备的元数据文件，用于记录当前脚本包的版本信息和更新历史，支持对脚本包的版本管理、升级比对和可观化控制。

---

### 1. 文件位置

```
/data/data/com.termux/files/home/servicemanager/<service_id>/VERSION.yaml
```

---

### 2. 基本结构

文件格式为 YAML，包括两部分：

```yaml
type: script_package
version: 1.3.2
history:
  - version: 1.3.2
    date: 2025-07-10
    changes:
      - 优化 autocheck 基本逻辑
      - 增加 MQTT 连接超时日志

  - version: 1.3.1
    date: 2025-07-06
    changes:
      - 修复 start.sh 无效时序 bug
```

---

### 3. 字段说明

| 字段        | 类型     | 说明                               |
| --------- | ------ | -------------------------------- |
| `type`    | string | 文件类型，组织检查使用，默认值 `script_package` |
| `version` | string | 当前脚本包版本，SemVer 格式                |
| `history` | array  | 更新历史列表，日期 + 改动列表                 |

---

### 4. 使用场景

* **autocheck.sh** 判断本地脚本包是否需要更新
* **autocheckall.sh** 进行全局版本同步和远程上报
* **Web Dashboard / Android App** 显示当前脚本包版本和更新历史

---

### 5. 其他要点

* YAML 文件必须可解析，不能包含 shell 语法
* `version` 必须和脚本包 tar.gz 名称中的版本一致
* `history` 可选，但建议保留最近至少 3 条记录

---

> 简单体量化的版本历史文件，便于本地模块进行更新准确对比、回滚旧版、控制更新频率。
