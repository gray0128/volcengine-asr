---
name: volcengine-asr
description: 使用火山引擎 Seed-ASR 2.0（豆包录音文件识别模型）识别语音消息。在消息进入大模型前拦截语音并转写为文本，对下游透明。支持所有平台（飞书、Telegram、钉钉等）的语音消息处理。使用场景：语音转文字、中文语音识别。
metadata: { "openclaw": { "requires": { "env": ["VOLC_API_KEY"] } } }
---

# Volcengine ASR Skill

## Overview

使用火山引擎 Seed-ASR 2.0 Standard（豆包录音文件识别模型2.0-标准版）来识别各平台发送的语音消息。通过 `beforeMessageProcessed` 钩子拦截语音，转写后伪装成普通文本消息，对下游大模型完全透明。支持所有平台（飞书、Telegram、钉钉等），无平台限制。
## Quick Install / Update

```bash
curl -fsSL https://raw.githubusercontent.com/gray0128/volcengine-asr/main/install.sh | bash
```

首次运行为安装，已安装时自动检测并提供更新选项。
## Quick Start

### 1. 配置环境变量

在 `~/.openclaw/openclaw.json` 中配置（插件启动时自动加载）：

```json
{
  "skills": {
    "entries": {
      "volcengine-asr": {
        "enabled": true,
        "env": {
          "VOLC_API_KEY": "你的火山引擎API Key",
          "S3_ENDPOINT": "你的S3端点URL",
          "S3_ACCESS_KEY_ID": "你的S3 Access Key ID",
          "S3_SECRET_ACCESS_KEY": "你的S3 Secret Access Key",
          "S3_BUCKET": "你的S3 Bucket名称",
          "S3_REGION": "auto"
        }
      }
    }
  }
}
```

### 2. 安装依赖

```bash
cd skills/volcengine-asr
npm install
```

## Core Workflow

```
平台语音消息（飞书/Telegram/钉钉等）
    ↓
[Skill 拦截: beforeMessageProcessed]
    ↓
[获取音频: 远程URL直接使用 / 本地文件上传S3]
    ↓
[提交火山引擎: submitTask()]
    ↓
[轮询结果: waitForResult()]
    ↓
[注入上下文: message.type = 'text', message.text = transcript]
    ↓
OpenClaw 大模型处理
```

## Seed-ASR 2.0 音频格式参考

详见 [references/audio-formats.md](references/audio-formats.md)

**关键要点：**
- ✅ 支持 Opus（封装为 ogg 容器）- 飞书默认格式
- ✅ 支持 MP3、WAV、PCM
- 🎯 推荐参数：16000 Hz 采样率，单声道，16 bit
- ⏱️ 音频时长建议 ≤ 60s

## Configuration

### Environment Variables

| 变量 | 必需 | 说明 |
|------|------|------|
| `VOLC_API_KEY` | ✅ | 火山引擎语音服务 API Key（UUID 格式） |
| `VOLC_RESOURCE_ID` | ❌ | 模型 Resource ID，默认 `volc.seedasr.auc`（2.0） |
| `S3_ENDPOINT` | ✅ | S3 兼容存储端点 URL |
| `S3_ACCESS_KEY_ID` | ✅ | S3 Access Key ID |
| `S3_SECRET_ACCESS_KEY` | ✅ | S3 Secret Access Key |
| `S3_BUCKET` | ❌ | S3 Bucket 名称，默认 `volcengine-asr` |
| `S3_REGION` | ❌ | S3 区域，默认 `auto` |
| `S3_PUBLIC_URL` | ❌ | S3 自定义公开域名，不设置则使用预签名 URL |

### 配置加载优先级

插件启动时按以下顺序加载配置（已有的系统环境变量不会被覆盖）：

1. 系统环境变量 (`process.env`)
2. `~/.openclaw/openclaw.json` → `skills.entries.volcengine-asr.env`
3. 项目目录下的 `.env` 文件

## Resources

### scripts/

- **volcengine.js** - 火山引擎 Seed-ASR 2.0 API 封装（x-api-key 鉴权、任务提交、结果轮询）
- **s3-client.js** - S3 兼容对象存储客户端（上传音频、生成预签名 URL、自动清理）
- **feishu-client.js** - 飞书 API 客户端（可选，用于直接下载飞书文件）

### references/

- **audio-formats.md** - Seed-ASR 2.0 支持的音频格式及参数详细说明
- **api-reference.md** - 火山引擎和飞书 API 参考文档

## Error Handling

### Graceful Degradation

当语音识别失败时，Skill 会优雅降级：

```javascript
context.message.text = "*(系统提示：语音消息解析失败，请尝试文字输入)*";
context.message.type = "text";
```

### Common Errors

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| 未配置 API Key | `VOLC_API_KEY` 未设置 | 检查 `~/.openclaw/openclaw.json` 中的配置 |
| S3 配置不完整 | S3 环境变量未设置 | 检查 `S3_ENDPOINT`、`S3_ACCESS_KEY_ID`、`S3_SECRET_ACCESS_KEY` |
| 音频格式不支持 | 平台语音格式问题 | 安装 ffmpeg 转码，见 [references/audio-formats.md](references/audio-formats.md) |
| API 调用失败 | 火山引擎鉴权问题 | 检查 API Key 权限和余额 |

## Development

### Testing the Hook

Skill 使用 `beforeMessageProcessed` 钩子，会在每条消息进入大模型前触发。

处理条件：
- `message.type === 'audio'` 或 `message.media` 中包含音频附件
- 不限平台，所有平台的语音消息均会处理

其他类型消息原样透传。
