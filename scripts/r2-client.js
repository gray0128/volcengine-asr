/**
 * Cloudflare R2 对象存储客户端
 * 用于将本地音频文件上传到 R2，通过预签名 URL 提供临时公开访问
 */

const { S3Client, PutObjectCommand, DeleteObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const crypto = require('crypto');

const BUCKET_NAME = 'volcengine-asr';
const PRESIGN_EXPIRES = 600; // 预签名 URL 有效期 10 分钟
const CLEANUP_MS = 15 * 60 * 1000; // 15 分钟后清理文件

function getR2Client() {
    const endpoint = process.env.R2_ENDPOINT;
    const accessKeyId = process.env.R2_ACCESS_KEY_ID;
    const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY;
    const region = process.env.R2_REGION || 'auto';

    if (!endpoint || !accessKeyId || !secretAccessKey) {
        throw new Error('R2 配置不完整，需要 R2_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY');
    }

    return new S3Client({
        region,
        endpoint,
        credentials: {
            accessKeyId,
            secretAccessKey,
        },
        forcePathStyle: true,
    });
}

/**
 * 上传文件到 R2 并返回预签名 URL
 * @param {Buffer} fileBuffer - 文件内容
 * @param {string} contentType - MIME 类型
 * @param {string} [ext] - 文件扩展名
 * @returns {Promise<{key: string, url: string}>}
 */
async function uploadAudio(fileBuffer, contentType, ext = '.ogg') {
    const client = getR2Client();
    const key = `audio/${crypto.randomUUID()}${ext}`;

    // 上传文件
    await client.send(new PutObjectCommand({
        Bucket: BUCKET_NAME,
        Key: key,
        Body: fileBuffer,
        ContentType: contentType,
    }));

    // 生成访问 URL
    let url;
    const publicBase = process.env.R2_PUBLIC_URL;
    if (publicBase) {
        // 自定义域名（公开访问），无需签名
        url = `${publicBase}/${key}`;
    } else {
        // 无自定义域名，使用预签名 URL（临时公开访问）
        url = await getSignedUrl(client, new GetObjectCommand({
            Bucket: BUCKET_NAME,
            Key: key,
        }), { expiresIn: PRESIGN_EXPIRES });
    }

    console.log(`[R2] 已上传: ${key} (${(fileBuffer.length / 1024).toFixed(1)} KB)`);
    return { key, url };
}

/**
 * 删除 R2 上的文件
 */
async function deleteAudio(key) {
    try {
        const client = getR2Client();
        await client.send(new DeleteObjectCommand({
            Bucket: BUCKET_NAME,
            Key: key,
        }));
        console.log(`[R2] 已清理: ${key}`);
    } catch (err) {
        console.warn(`[R2] 清理失败 (${key}):`, err.message);
    }
}

/**
 * 上传并设置自动清理
 */
async function uploadWithAutoCleanup(fileBuffer, contentType, ext = '.ogg') {
    const result = await uploadAudio(fileBuffer, contentType, ext);

    // 异步定时清理
    setTimeout(() => {
        deleteAudio(result.key).catch(() => { });
    }, CLEANUP_MS);

    return result;
}

module.exports = {
    uploadAudio,
    deleteAudio,
    uploadWithAutoCleanup,
};
