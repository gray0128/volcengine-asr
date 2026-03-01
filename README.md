# Doubao ASR

基于火山引擎 Seed-ASR 2.0（豆包大模型录音文件识别标准版）的 OpenClaw 语音识别插件。

自动拦截各平台（飞书、Telegram、钉钉等）的语音消息，转写为文本后注入上下文，对下游大模型完全透明。

## 工作流程

```
平台语音消息（飞书/Telegram/钉钉等）
    ↓
Skill 拦截 (beforeMessageProcessed)
    ↓
获取音频（远程URL直接使用 / 本地文件上传R2）
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

## 快速开始

### 1. 安装依赖

```bash
npm install
```

### 2. 配置环境变量

复制 `.env.example` 为 `.env`，填入真实配置：

```json
{
  "skills": {
    "entries": {
      "doubao-asr": {
        "enabled": true,
        "env": {
          "VOLC_API_KEY": "你的火山引擎API Key (UUID格式)",
          "R2_ENDPOINT": "你的Cloudflare R2端点URL",
          "R2_ACCESS_KEY_ID": "你的R2 Access Key ID",
          "R2_SECRET_ACCESS_KEY": "你的R2 Secret Access Key",
          "R2_REGION": "auto"
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
| `R2_ENDPOINT` | 是 | Cloudflare R2 端点 URL |
| `R2_ACCESS_KEY_ID` | 是 | R2 Access Key ID |
| `R2_SECRET_ACCESS_KEY` | 是 | R2 Secret Access Key |
| `R2_REGION` | 否 | R2 区域，默认 `auto` |
| `R2_PUBLIC_URL` | 否 | R2 自定义公开域名，不设置则使用预签名 URL |

## 项目结构

```
├── index.js                  # Skill 主入口，beforeMessageProcessed 钩子
├── scripts/
│   ├── volcengine.js         # 火山引擎 Seed-ASR 2.0 API 封装
│   ├── r2-client.js          # Cloudflare R2 对象存储客户端
│   └── feishu-client.js      # 飞书 API 客户端（可选）
├── references/
│   ├── audio-formats.md      # 音频格式参考
│   └── api-reference.md      # API 接口参考
├── .env.example              # 环境变量模板
├── SKILL.md                  # OpenClaw Skill 元数据
└── SYSTEMD_SETUP.txt         # systemd 部署指南
```

## 错误处理

语音识别失败时自动降级，将错误信息作为文本消息注入，不会阻断正常消息流。

## 许可证

MIT
