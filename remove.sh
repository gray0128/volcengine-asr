#!/usr/bin/env bash
set -euo pipefail

echo ""
echo -e "\033[1;33m[!] 正在移除旧版 Volcengine ASR Skill...\033[0m"

OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
SKILL_DIR="$OPENCLAW_DIR/skills/volcengine-asr"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"

if [ -d "$SKILL_DIR" ]; then
    rm -rf "$SKILL_DIR"
    echo -e "  \033[0;32m[OK]\033[0m 已删除源码目录: $SKILL_DIR"
else
    echo -e "  \033[0;34m[i]\033[0m 未找到源码目录: $SKILL_DIR"
fi

if [ -f "$CONFIG_FILE" ]; then
    if command -v node &> /dev/null; then
        node -e "
const fs = require('fs');
const file = '$CONFIG_FILE';
try {
  let config = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (config.skills && config.skills.entries && config.skills.entries['volcengine-asr']) {
    delete config.skills.entries['volcengine-asr'];
    fs.writeFileSync(file, JSON.stringify(config, null, 2) + '\n');
    console.log('  \033[0;32m[OK]\033[0m 已从 openclaw.json 中移除 volcengine-asr 配置');
  } else {
    console.log('  \033[0;34m[i]\033[0m openclaw.json 中没有找到相关配置');
  }
} catch(e) {
  console.error('  \033[0;31m[X]\033[0m 处理 JSON 失败: ' + e.message);
}
"
    else
        echo -e "  \033[0;31m[X]\033[0m 未找到 Node.js，无法自动修改 $CONFIG_FILE"
        echo -e "       请手动编辑该文件并移除 skills.entries.volcengine-asr"
    fi
else
    echo -e "  \033[0;34m[i]\033[0m 配置文件不存在: $CONFIG_FILE"
fi

echo ""
echo -e "\033[1;32m卸载完成！如果旧版正在运行，请执行 openclaw gateway restart 重启网关。\033[0m"
echo ""
