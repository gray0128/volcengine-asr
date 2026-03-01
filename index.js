/**
 * Volcengine ASR Skill for OpenClaw
 * 使用火山引擎 Seed-ASR 2.0 (大模型录音文件识别标准版) 识别飞书语音消息
 */

const fs = require('fs').promises;
const path = require('path');
const { submitTask, waitForResult } = require('./scripts/volcengine');
const { uploadWithAutoCleanup } = require('./scripts/r2-client');

function isConfigured() {
  return !!process.env.VOLC_API_KEY;
}

/**
 * 根据文件扩展名推断音频格式参数
 */
function inferAudioFormat(filePath, contentType) {
  const ext = path.extname(filePath).toLowerCase();

  if (ext === '.ogg' || contentType?.includes('ogg')) {
    return { format: 'ogg', codec: 'opus', ext: '.ogg', mime: 'audio/ogg' };
  }
  if (ext === '.mp3' || contentType?.includes('mp3') || contentType?.includes('mpeg')) {
    return { format: 'mp3', codec: 'raw', ext: '.mp3', mime: 'audio/mpeg' };
  }
  if (ext === '.wav' || contentType?.includes('wav')) {
    return { format: 'wav', codec: 'raw', ext: '.wav', mime: 'audio/wav' };
  }
  if (ext === '.m4a' || contentType?.includes('m4a') || contentType?.includes('mp4')) {
    // M4A (AAC) 也使用 mp3 格式参数（API 支持的最接近格式）
    return { format: 'mp3', codec: 'raw', ext: '.m4a', mime: 'audio/mp4' };
  }
  // 默认按 ogg/opus 处理（飞书语音默认格式）
  return { format: 'ogg', codec: 'opus', ext, mime: contentType || 'audio/ogg' };
}

module.exports = {
  name: 'volcengine-asr',
  version: '2.0.0',
  description: 'Intercept Feishu audio and transcribe via Volcengine Seed-ASR 2.0 (BigModel Standard)',

  hooks: {
    /**
     * 在消息进入大模型前拦截处理
     */
    'beforeMessageProcessed': async (context) => {
      const { message, platform } = context;

      // 调试日志
      console.log('[Volcengine-ASR] 收到消息:', {
        type: message.type,
        platform: platform?.id,
        messageKeys: Object.keys(message),
        media: message.media?.length ? `${message.media.length} 个附件` : '无附件'
      });

      // 检查是否为音频消息
      const isAudioMessage = message.type === 'audio';
      const hasAudioMedia = message.media && message.media.some(m =>
        m.contentType?.startsWith('audio/') ||
        m.placeholder === '<media:audio>'
      );

      if (!isAudioMessage && !hasAudioMedia) {
        return context;
      }

      // 检查配置
      if (!isConfigured()) {
        console.warn('[Volcengine-ASR] 未配置 VOLC_API_KEY');
        context.message.text = '*(系统提示：语音识别功能未配置，请使用文字输入)*';
        context.message.type = 'text';
        return context;
      }

      try {
        console.log('[Volcengine-ASR] 开始处理语音消息');

        let audioUrl;
        let audioFormat;

        if (message.media && message.media.length > 0) {
          const audioMedia = message.media.find(m =>
            m.contentType?.startsWith('audio/') ||
            m.placeholder === '<media:audio>'
          );

          if (audioMedia) {
            audioFormat = inferAudioFormat(
              audioMedia.path || audioMedia.url || '',
              audioMedia.contentType
            );

            if (audioMedia.url) {
              // 远程 URL 直接使用
              audioUrl = audioMedia.url;
              console.log(`[Volcengine-ASR] 使用远程 URL: ${audioUrl}`);
            } else if (audioMedia.path) {
              // 本地文件 → 上传到 R2 → 获取公开 URL
              console.log(`[Volcengine-ASR] 本地文件，上传到 R2: ${audioMedia.path}`);
              const fileBuffer = await fs.readFile(audioMedia.path);
              const r2Result = await uploadWithAutoCleanup(fileBuffer, audioFormat.mime, audioFormat.ext);
              audioUrl = r2Result.url;
              console.log(`[Volcengine-ASR] R2 URL: ${audioUrl}`);
            }
          }
        }

        if (!audioUrl) {
          throw new Error('未找到音频数据');
        }

        // 提交识别任务
        const requestId = await submitTask(audioUrl, {
          format: audioFormat.format,
          codec: audioFormat.codec,
          rate: 16000,
          channel: 1,
        });
        console.log(`[Volcengine-ASR] 任务已提交: ${requestId}`);

        // 等待并获取结果
        const transcriptText = await waitForResult(requestId);
        console.log(`[Volcengine-ASR] 识别结果: ${transcriptText}`);

        // 注入上下文
        context.message.type = 'text';
        context.message.text = transcriptText || '*(语音识别结果为空)*';
        context.message.metadata = {
          ...context.message.metadata,
          original_type: 'audio',
          asr_provider: 'volcengine-seed-asr-2.0',
          request_id: requestId
        };

      } catch (error) {
        console.error('[Volcengine-ASR] 音频解析失败:', error);
        context.message.text = `*(系统提示：语音消息解析失败: ${error.message})*`;
        context.message.type = 'text';
      }

      return context;
    }
  }
};
