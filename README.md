# Volcengine ASR

基于火山引擎 Seed-ASR 2.0（豆包大模型录音文件识别标准版）的 OpenClaw 语音识别插件。

自动拦截各平台（飞书、Telegram、钉钉等）的语音消息，转写为文本后注入上下文，对下游大模型完全透明。支持所有 S3 兼容存储（Cloudflare R2、AWS S3、MinIO 等）。

## 工作流程

```
平台语音消息（飞书/Telegram/钉钉等）
    ↓
Skill 拦截 (beforeMessageProcessed)
    ↓
获取音频（远程URL直接使用 / 本地文件上传S3）
    ↓
提交火山引擎 Seed-ASR 2.0 识别
    ↓
轮询获取识别结果
    ↓
注入文本到消息上下文 → 大模型处理
```

## 支持的音频格式

| 格式 | 参数 | 说明 |
|------|------|------|
| Opus | `format=ogg` + `codec=opus` | 飞书/Telegram 默认格式 |
| MP3 | `format=mp3` | 通用格式 |
| WAV | `format=wav` | 无损格式 |
| M4A | `format=mp3` | AAC 容器格式 |

推荐参数：16000 Hz 采样率，单声道，16 bit，音频时长 ≤ 60s。

## 安装 / 更新

```bash
curl -fsSL https://raw.githubusercontent.com/gray0128/volcengine-asr/main/install.sh | bash
```

- **首次安装**：自动引导配置火山引擎 API Key 和 S3 存储参数，也可跳过后手动添加
- **更新**：检测到已安装时自动执行 `git pull` + `npm install`，可选重启网关

## 手动安装

### 1. 克隆并安装依赖

```bash
cd ~/.openclaw/skills
git clone https://github.com/gray0128/volcengine-asr.git volcengine-asr
cd volcengine-asr
npm install
```

### 2. 配置环境变量

在 `~/.openclaw/openclaw.json` 中添加 skill 配置（插件启动时会自动从该文件加载）：

```json
{
  "skills": {
    "entries": {
      "volcengine-asr": {
        "enabled": true,
        "env": {
          "VOLC_API_KEY": "你的火山引擎API Key (UUID格式)",
          "S3_ENDPOINT": "你的S3端点URL",
          "S3_ACCESS_KEY_ID": "你的S3 Access Key ID",
          "S3_SECRET_ACCESS_KEY": "你的S3 Secret Access Key",
          "S3_BUCKET": "你的S3 Bucket名称",
          "S3_REGION": "auto，或者你的S3 Bucket区域"
        }
      }
    }
  }
}
```

## 环境变量

| 变量 | 必需 | 说明 |
|------|------|------|
| `VOLC_API_KEY` | 是 | 火山引擎语音服务 API Key（UUID 格式） |
| `VOLC_RESOURCE_ID` | 否 | 模型 Resource ID，默认 `volc.seedasr.auc` |
| `S3_ENDPOINT` | 是 | S3 兼容存储端点 URL |
| `S3_ACCESS_KEY_ID` | 是 | S3 Access Key ID |
| `S3_SECRET_ACCESS_KEY` | 是 | S3 Secret Access Key |
| `S3_BUCKET` | 否 | S3 Bucket 名称，默认 `volcengine-asr` |
| `S3_REGION` | 否 | S3 区域，默认 `auto` |
| `S3_PUBLIC_URL` | 否 | S3 自定义公开域名，不设置则使用预签名 URL |

## 本地测试

项目自带测试脚本 `test.js`，可使用项目中的 OGG 音频文件走完 **S3 上传 → 火山引擎 ASR 识别** 的完整流程，无需部署到 OpenClaw 即可验证配置是否正确。

### 用法

```bash
# 默认测试 test-audio.ogg
node test.js

# 指定测试文件
node test.js test-keshan.ogg

# 测试项目目录下所有 OGG 文件
node test.js all
```

### 测试流程

1. **加载配置** - 从 `.env` 文件读取环境变量（火山引擎 API Key、S3 存储凭证等）
2. **读取音频** - 读取指定的本地 OGG 文件
3. **推断格式** - 根据文件扩展名自动推断音频编码参数（format、codec 等）
4. **上传 S3** - 将音频文件上传到 S3 兼容存储，获取临时预签名 URL
5. **提交 ASR** - 调用火山引擎 Seed-ASR 2.0 API 提交识别任务
6. **轮询结果** - 周期性查询任务状态，直到识别完成
7. **输出结果** - 打印识别文本、上传耗时和识别耗时，多文件时输出汇总

测试通过即表示环境变量、S3 存储和火山引擎 API 配置均正确。

## 项目结构

```
├── index.js                  # Skill 主入口，beforeMessageProcessed 钩子
├── test.js                   # 本地测试脚本
├── test-audio.ogg            # 测试用音频文件
├── test-keshan.ogg           # 测试用音频文件
├── scripts/
│   ├── volcengine.js         # 火山引擎 Seed-ASR 2.0 API 封装
│   ├── s3-client.js          # S3 兼容对象存储客户端
│   └── feishu-client.js      # 飞书 API 客户端（可选）
├── references/
│   ├── audio-formats.md      # 音频格式参考
│   └── api-reference.md      # API 接口参考
├── install.sh                 # 一键安装/更新脚本
├── .env.example              # 环境变量模板
├── SKILL.md                  # OpenClaw Skill 元数据
└── SYSTEMD_SETUP.txt         # systemd 部署指南
```

## 错误处理

语音识别失败时自动降级，将错误信息作为文本消息注入，不会阻断正常消息流。

## 许可证

MIT
