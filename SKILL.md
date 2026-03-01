---
name: volcengine-asr
description: |
  使用火山引擎 Seed-ASR 2.0（豆包录音文件识别模型）拦截各平台发送语音消息，自动识别转写文字，为下游 AI 大模型提供干净纯文本环境。
  使用此 Skill 可以让大模型在无需多余步骤的情况下直接“听”懂用户的语音指令。
metadata: { "openclaw": { "requires": { "env": ["VOLC_API_KEY"] } } }
---

# Volcengine ASR Skill

## 1. Skill 作用与适用场景

本技能作为**前置处理器**，主动接管在不同平台（飞书、Telegram、钉钉等）发给开放终端大模型的语音文件（`message.type === 'audio'` 或 `message.media` 含语音）。通过拦截钩子将其提取、转写，然后无缝把上下文替换成普通文本消息供大模型直接回答。

这对作为 AI 助理的你而言，它彻底屏蔽了处理上游“音频格式处理”、“API对接”与“格式降级”的麻烦。

## 2. Agent 使用指引 (How it affects you)

你（大模型助理）**无需主动使用任何 Tool 来调用此 Skill**。此 Skill 已经自动挂载为全局拦截。

当用户对你发送语音时：
1. 本 Skill 会在钩子（`beforeMessageProcessed`）层截获它。
2. 转写结果将会自动填充至用户的 `message.text` 中，并附带元数据 `asr_provider` 通知你。
3. 当你最终收到用户 Prompt 时，你看到的完全是一句正常由人类“打字键入”的文本。

你需要做的：
- 当识别成功时：正常解答用户的语音文本诉求即可，就像用户发了普通的文字问题一样。
- 当识别失败时：你收到的提示词会类似于 `*(系统提示：语音消息解析失败，请尝试文字输入)*`。看到此句时，请你耐心回复并提醒用户遇到了系统识别错误，建议重读或打字沟通。

## 3. Core Capabilities / Audio Spec

支持音频范围：
- Ogg 容器内的 Opus，这是大部分即时通讯如 Web/飞书/Telegram 的默认语音。
- 通用 MP3 / M4A / WAV等格式。
- 时长限制：建议拦截处理在 60s 内的语音对象。

## 4. 依赖项列表 (For Information Only)

作为运行保障，系统环境（`~/.openclaw/openclaw.json`）已经自动挂载在技能配置中，你无需操心：
- `VOLC_API_KEY`: 火山引擎服务秘钥。
- S3 Bucket/Credential 系参数：由于 Seed-ASR API 需要可路由下发的公网大文件 URL，故需经过一层 S3。
