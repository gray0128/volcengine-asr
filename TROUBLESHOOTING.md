# 常见问题与排查指南 (Troubleshooting)

> 版本: v1.1 | 更新时间: 2026-03-01 18:28:00

本文档记录了基于 OpenClaw Plugin 架构开发和安装本插件（`volcengine-asr`）时，可能会遇到的由 CLI 验证机制引入的一些典型错误及其解决方案。

## 历史排查记录：Plugin 注册及配置校验失败

在将本仓库从旧版 Skill 架构重构至新版 Plugin 架构时，系统多次因为 manifest 及 package 层面不满足 OpenClaw CLI 的严格校验而导致网关无限崩溃或安装失败。下面是错误全览及对应的修复办法：

### 1. `package.json missing openclaw.extensions`

**错误现象：**
在执行 `openclaw plugins install ./` 进行本地安装时，CLI 直接中断并抛出：
`Error: package.json missing openclaw.extensions`

**原因分析：**
新版 OpenClaw CLI 在加载本地插件源码时，会强制读取项目根目录的 `package.json`。如果没有找到 `openclaw.extensions` 声明，或者该声明不是一个 **Array（数组）** 格式，解析器就会抛错退出。

**解决方案：**
在 `package.json` 追加符合格式要求的注册映射，指向插件的**代码入口文件**（非 manifest）。需确保它的值是**字符串数组**。
```json
  "openclaw": {
    "extensions": [
      "./index.js"
    ]
  }
```
> **注意：** `extensions` 数组中的每个条目应指向代码入口文件（如 `./index.js`），OpenClaw 会自动在同级目录查找 `openclaw.plugin.json` manifest。不要将 manifest 文件本身放进此数组，否则会导致后续的 "plugin not found" 错误（见第 4 条）。

---

### 2. `plugin manifest requires configSchema`

**错误现象：**
插件目录成功被拉取，但在网关启动阶段遇到诊断报错，导致 `doctor` 将配置文件标记为“损坏”并拒绝加载。
```text
  Config invalid
  File: ~/.openclaw/openclaw.json
  Problem:
  - plugins: plugin: plugin manifest requires configSchema
```

**原因分析：**
除了 `package.json`，OpenClaw 通过扩展机制加载核心 `openclaw.plugin.json` （Plugin Manifest）时，强制要求该文件必须拥有 `configSchema` 字段，且它必须是一个 **对象（Object）**，用于告诉主程序这个查件接受哪些配置。如果没有定义，哪怕这个插件根本没有自定义设置，OpenClaw 也会拒载。

**解决方案：**
在 `openclaw.plugin.json` 中补上一个空的 Object 结构适配其解析要求：
```json
    "configSchema": {
        "type": "object",
        "properties": {}
    }
```

---

### 3. `Unrecognized key: "env"`

**错误现象：**
解决了 Manifest 解析后，重启 Gateway 时系统依然报错，指出自定义配置文件键名无效，甚至还会强制关闭正在运行的进程。
```text
  Invalid config at /home/bobocai/.openclaw/openclaw.json:
- plugins.entries.volcengine-asr: Unrecognized key: "env"
```

**原因分析：**
旧时代的 OpenClaw Skill 通过 `skills.entries["id"].env` 来读取用户的配置变量。而切换至 Plugin 后，CLI 实行了统一的强校验，规范所有由插件引入的配置变量必须放置在 `plugins.entries["id"].config` 节点中。

**解决方案：**
更新一键安装脚本及手动配置文件书写规范，将最终生成的 JSON 修改为以下结构：
```json
    "plugins": {
      "entries": {
        "volcengine-asr": {
          "enabled": true,
          "config": {
            "VOLC_API_KEY": "..."
          }
        }
      }
    }
```

---

### 4. `plugin not found: volcengine-asr (stale config entry ignored)`

**错误现象：**
安装成功后，Gateway 启动或执行 `openclaw plugins list` 时反复出现：
```text
Config warnings:
- plugins.entries.volcengine-asr: plugin not found: volcengine-asr
  (stale config entry ignored; remove it from plugins config)
```

**原因分析：**
`package.json` 中 `openclaw.extensions` 指向了 manifest 文件（`./openclaw.plugin.json`）而非代码入口文件（`./index.js`）。OpenClaw 的插件发现机制期望 `extensions` 数组中的每一项都是**可执行的代码入口**，它会自动在入口文件同级目录查找 `openclaw.plugin.json`。指向 manifest 会导致 OpenClaw 无法解析插件入口点，从而判定 "plugin not found"。

**解决方案：**
将 `package.json` 中的 `openclaw.extensions` 修改为指向代码入口：
```diff
  "openclaw": {
    "extensions": [
-     "./openclaw.plugin.json"
+     "./index.js"
    ]
  }
```
修改后需重新执行 `openclaw plugins install` 并重启 Gateway。

---

### 5. `volcengine-asr missing register/activate export`

**错误现象：**
解决 "plugin not found" 后，`openclaw plugins list` 显示插件状态为 `error`，日志提示：
```text
[plugins] volcengine-asr missing register/activate export
```

**原因分析：**
OpenClaw 的插件加载器不使用默认导出（`export default` 或 `module.exports = function`），而是查找名为 `register`（或 `activate`）的**命名导出**。如果入口文件使用了 `export default function(api)` 或 `module.exports = function(api)` 这样的匿名/默认导出，OpenClaw 将无法识别到注册函数。

**解决方案：**
将入口文件（`index.js`）的导出方式改为命名导出：
```diff
- export default function (api) {
+ exports.register = function (api) {
```
> 本项目使用 CommonJS (`require`) 风格，因此采用 `exports.register` 而非 ESM 的 `export function register`。与项目中其他模块（`volcengine.js`、`s3-client.js`）的导出风格保持一致。

---

### 6. 配置 Key 名称不匹配导致功能异常

**错误现象：**
插件安装成功、状态正常，但发送语音后没有任何响应，日志中出现 S3 配置不完整的报错。

**原因分析：**
`~/.openclaw/openclaw.json` 中配置的 Key 名称与代码中实际读取的不一致。常见的错误配对：

| 错误写法 | 正确写法 |
|---------|--------|
| `S3_ACCESS_KEY` | `S3_ACCESS_KEY_ID` |
| `S3_SECRET_KEY` | `S3_SECRET_ACCESS_KEY` |

**解决方案：**
确保配置文件中的 Key 名称与下表完全一致：
```json
"config": {
  "VOLC_API_KEY": "你的火山引擎 API Key",
  "S3_ENDPOINT": "你的 S3 兼容存储端点",
  "S3_ACCESS_KEY_ID": "你的 Access Key ID",
  "S3_SECRET_ACCESS_KEY": "你的 Secret Access Key",
  "S3_BUCKET": "volcengine-asr",
  "S3_REGION": "auto"
}
```

---

## 解决“Config invalid”循环锁定的步骤

一旦遇到以上任意由于验证不通过而留下的残留数据，OpenClaw 会将 `~/.openclaw/openclaw.json` 判定为受损状态并阻止后续的所有 CLI 操作。

如遇此情况，必须先彻底清理损坏项：

1. **手动移除受损配置**，或直接执行本仓库内置的强清理脚本（会把旧版及所有残留记录抹除）：
   ```bash
   curl -fsSL https://raw.githubusercontent.com/gray0128/volcengine-asr/main/remove.sh | bash
   ```
2. 使用 OpenClaw 自带的 Doctor 自动梳理缓存：
   ```bash
   openclaw doctor --fix
   ```
3. 最后重新通过正常的安装流程（或 `npm install && openclaw plugins install ./`）将修正后的模块注入：
   ```bash
   curl -fsSL https://raw.githubusercontent.com/gray0128/volcengine-asr/main/install.sh | bash
   ```
4. 重启网关：
   ```bash
   openclaw gateway restart
   ```

---

## 变更历史

| 版本 | 时间 | 变更内容 |
|------|------|----------|
| v1.0 | 2026-03-01 09:50:00 | 初始文档，记录 manifest/configSchema/env 三类校验错误 |
| v1.1 | 2026-03-01 18:28:00 | 新增第 4-6 条：extensions 指向错误、register 导出缺失、配置 Key 名称不匹配 |
