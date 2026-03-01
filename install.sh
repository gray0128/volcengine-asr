#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Volcengine ASR Skill 安装脚本
# 使用方式: curl -fsSL <URL>/install.sh | bash
# =============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # 重置颜色

# 图标
CHECK="${GREEN}[OK]${NC}"
CROSS="${RED}[X]${NC}"
INFO="${BLUE}[i]${NC}"
WARN="${YELLOW}[!]${NC}"

# 默认配置
REPO_URL="https://github.com/gray0128/volcengine-asr.git"
OPENCLAW_DIR="${OPENCLAW_DIR:-$HOME/.openclaw}"
SKILL_NAME="volcengine-asr"
SKILL_DIR=""
CONFIG_FILE=""

# -----------------------------------------------------------------------------
# 工具函数
# -----------------------------------------------------------------------------

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║        Volcengine ASR Installer          ║"
    echo "  ║   火山引擎 Seed-ASR 2.0 语音识别插件    ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${BOLD}[$1/$TOTAL_STEPS] $2${NC}"
    echo -e "${DIM}$(printf '%.0s─' {1..50})${NC}"
}

prompt_input() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    local is_secret="${4:-false}"

    if [ -n "$default" ]; then
        echo -ne "  ${prompt} ${DIM}(默认: ${default})${NC}: "
    else
        echo -ne "  ${prompt}: "
    fi

    if [ "$is_secret" = "true" ]; then
        read -rs input_value
        echo ""
    else
        read -r input_value
    fi

    if [ -z "$input_value" ] && [ -n "$default" ]; then
        input_value="$default"
    fi

    eval "$var_name='$input_value'"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"

    if [ "$default" = "y" ]; then
        echo -ne "  ${prompt} ${DIM}[Y/n]${NC}: "
    else
        echo -ne "  ${prompt} ${DIM}[y/N]${NC}: "
    fi

    read -r answer
    answer="${answer:-$default}"

    case "$answer" in
        [Yy]* ) return 0 ;;
        * ) return 1 ;;
    esac
}

check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "  $CHECK $1 $(command -v "$1")"
        return 0
    else
        echo -e "  $CROSS $1 未找到"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# 步骤 1: 环境检查
# -----------------------------------------------------------------------------

check_prerequisites() {
    print_step 1 "检查运行环境"

    local has_error=false

    check_command "node" || has_error=true
    check_command "npm" || has_error=true
    check_command "git" || has_error=true

    if [ "$has_error" = true ]; then
        echo -e "\n  $CROSS 缺少必要的依赖，请先安装后重试"
        exit 1
    fi

    # 检查 Node.js 版本
    local node_version
    node_version=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$node_version" -lt 18 ]; then
        echo -e "  $CROSS Node.js 版本需要 >= 18，当前: $(node -v)"
        exit 1
    fi
    echo -e "  $CHECK Node.js 版本: $(node -v)"
}

# -----------------------------------------------------------------------------
# 步骤 2: 确定安装位置
# -----------------------------------------------------------------------------

detect_install_path() {
    print_step 2 "确定安装位置"

    # 检测 OpenClaw 目录
    if [ -d "$OPENCLAW_DIR" ]; then
        echo -e "  $CHECK 检测到 OpenClaw 目录: ${OPENCLAW_DIR}"
    else
        echo -e "  $WARN 未检测到 OpenClaw 目录: ${OPENCLAW_DIR}"
        if prompt_yes_no "是否使用该路径创建?" "y"; then
            mkdir -p "$OPENCLAW_DIR"
            echo -e "  $CHECK 已创建: ${OPENCLAW_DIR}"
        else
            prompt_input "请输入 OpenClaw 目录路径" OPENCLAW_DIR
            mkdir -p "$OPENCLAW_DIR"
        fi
    fi

    SKILL_DIR="${OPENCLAW_DIR}/skills/${SKILL_NAME}"
    CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"

    echo -e "  ${INFO} Skill 安装目录: ${SKILL_DIR}"
    echo -e "  ${INFO} 配置文件路径: ${CONFIG_FILE}"

    # 检查是否已安装
    if [ -d "$SKILL_DIR" ]; then
        echo -e "\n  $WARN Skill 目录已存在: ${SKILL_DIR}"
        if prompt_yes_no "是否覆盖安装?" "n"; then
            rm -rf "$SKILL_DIR"
        else
            echo -e "  安装已取消"
            exit 0
        fi
    fi
}

# -----------------------------------------------------------------------------
# 步骤 3: 配置参数
# -----------------------------------------------------------------------------

collect_config() {
    print_step 3 "配置 Skill 参数"

    echo -e "  ${INFO} 安装此 Skill 需要以下配置:"
    echo ""
    echo -e "  ${BOLD}必需参数:${NC}"
    echo -e "    - VOLC_API_KEY        火山引擎 API Key (UUID 格式)"
    echo -e "    - R2_ENDPOINT         Cloudflare R2 端点 URL"
    echo -e "    - R2_ACCESS_KEY_ID    R2 Access Key ID"
    echo -e "    - R2_SECRET_ACCESS_KEY R2 Secret Access Key"
    echo ""
    echo -e "  ${BOLD}可选参数:${NC}"
    echo -e "    - R2_REGION           R2 区域 (默认: auto)"
    echo -e "    - R2_PUBLIC_URL       R2 自定义公开域名"
    echo -e "    - VOLC_RESOURCE_ID    模型 Resource ID (默认: volc.seedasr.auc)"
    echo ""

    SKIP_CONFIG=false
    if ! prompt_yes_no "现在配置这些参数?" "y"; then
        SKIP_CONFIG=true
        echo -e "\n  ${INFO} 已跳过配置，安装完成后请手动添加"
        return
    fi

    echo -e "\n  ${BOLD}-- 火山引擎配置 --${NC}"
    prompt_input "VOLC_API_KEY" VOLC_API_KEY
    while [ -z "${VOLC_API_KEY:-}" ]; do
        echo -e "  ${WARN} VOLC_API_KEY 为必填项"
        prompt_input "VOLC_API_KEY" VOLC_API_KEY
    done
    prompt_input "VOLC_RESOURCE_ID" VOLC_RESOURCE_ID "volc.seedasr.auc"

    echo -e "\n  ${BOLD}-- Cloudflare R2 配置 --${NC}"
    prompt_input "R2_ENDPOINT" R2_ENDPOINT
    while [ -z "${R2_ENDPOINT:-}" ]; do
        echo -e "  ${WARN} R2_ENDPOINT 为必填项"
        prompt_input "R2_ENDPOINT" R2_ENDPOINT
    done
    prompt_input "R2_ACCESS_KEY_ID" R2_ACCESS_KEY_ID
    while [ -z "${R2_ACCESS_KEY_ID:-}" ]; do
        echo -e "  ${WARN} R2_ACCESS_KEY_ID 为必填项"
        prompt_input "R2_ACCESS_KEY_ID" R2_ACCESS_KEY_ID
    done
    prompt_input "R2_SECRET_ACCESS_KEY" R2_SECRET_ACCESS_KEY "" "true"
    while [ -z "${R2_SECRET_ACCESS_KEY:-}" ]; do
        echo -e "  ${WARN} R2_SECRET_ACCESS_KEY 为必填项"
        prompt_input "R2_SECRET_ACCESS_KEY" R2_SECRET_ACCESS_KEY "" "true"
    done
    prompt_input "R2_REGION" R2_REGION "auto"
    prompt_input "R2_PUBLIC_URL (可选，直接回车跳过)" R2_PUBLIC_URL ""
}

# -----------------------------------------------------------------------------
# 步骤 4: 下载并安装
# -----------------------------------------------------------------------------

install_skill() {
    print_step 4 "下载并安装 Skill"

    echo -e "  正在克隆仓库..."
    mkdir -p "$(dirname "$SKILL_DIR")"
    git clone --depth 1 "$REPO_URL" "$SKILL_DIR" 2>&1 | while read -r line; do
        echo -e "  ${DIM}${line}${NC}"
    done
    echo -e "  $CHECK 仓库克隆完成"

    echo -e "  正在安装依赖..."
    cd "$SKILL_DIR"
    npm install --production 2>&1 | tail -1 | while read -r line; do
        echo -e "  ${DIM}${line}${NC}"
    done
    echo -e "  $CHECK 依赖安装完成"
}

# -----------------------------------------------------------------------------
# 步骤 5: 写入配置
# -----------------------------------------------------------------------------

write_config() {
    print_step 5 "写入配置"

    if [ "$SKIP_CONFIG" = true ]; then
        echo -e "  ${INFO} 已跳过自动配置"
        print_manual_config_guide
        return
    fi

    # 构建 env JSON 片段
    local env_json="{"
    env_json+="\"VOLC_API_KEY\":\"${VOLC_API_KEY}\""

    if [ "${VOLC_RESOURCE_ID}" != "volc.seedasr.auc" ]; then
        env_json+=",\"VOLC_RESOURCE_ID\":\"${VOLC_RESOURCE_ID}\""
    fi

    env_json+=",\"R2_ENDPOINT\":\"${R2_ENDPOINT}\""
    env_json+=",\"R2_ACCESS_KEY_ID\":\"${R2_ACCESS_KEY_ID}\""
    env_json+=",\"R2_SECRET_ACCESS_KEY\":\"${R2_SECRET_ACCESS_KEY}\""

    if [ "${R2_REGION}" != "auto" ]; then
        env_json+=",\"R2_REGION\":\"${R2_REGION}\""
    fi

    if [ -n "${R2_PUBLIC_URL:-}" ]; then
        env_json+=",\"R2_PUBLIC_URL\":\"${R2_PUBLIC_URL}\""
    fi

    env_json+="}"

    # 构建 skill 配置片段
    local skill_json="{\"enabled\":true,\"env\":${env_json}}"

    if [ -f "$CONFIG_FILE" ]; then
        echo -e "  ${INFO} 检测到已有配置文件: ${CONFIG_FILE}"
        # 使用 node 合并 JSON 配置
        node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('${CONFIG_FILE}', 'utf8'));
if (!config.skills) config.skills = {};
if (!config.skills.entries) config.skills.entries = {};
config.skills.entries['${SKILL_NAME}'] = ${skill_json};
fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2) + '\n');
console.log('  配置已合并写入');
"
    else
        echo -e "  ${INFO} 创建新配置文件: ${CONFIG_FILE}"
        node -e "
const fs = require('fs');
const config = { skills: { entries: { '${SKILL_NAME}': ${skill_json} } } };
fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2) + '\n');
console.log('  配置已写入');
"
    fi

    echo -e "  $CHECK 配置写入完成"
}

# -----------------------------------------------------------------------------
# 手动配置引导
# -----------------------------------------------------------------------------

print_manual_config_guide() {
    echo ""
    echo -e "  ${BOLD}手动配置方法:${NC}"
    echo ""
    echo -e "  编辑 OpenClaw 配置文件:"
    echo -e "  ${CYAN}${CONFIG_FILE}${NC}"
    echo ""
    echo -e "  在配置文件中添加或合并以下内容到 ${BOLD}skills.entries${NC} 字段:"
    echo ""
    echo -e "  ${DIM}// ${CONFIG_FILE}${NC}"
    echo -e "  {"
    echo -e "    \"skills\": {"
    echo -e "      \"entries\": {"
    echo -e "        ${YELLOW}\"volcengine-asr\": {${NC}"
    echo -e "          ${YELLOW}\"enabled\": true,${NC}"
    echo -e "          ${YELLOW}\"env\": {${NC}"
    echo -e "            ${YELLOW}\"VOLC_API_KEY\": \"你的火山引擎API Key\",${NC}"
    echo -e "            ${YELLOW}\"R2_ENDPOINT\": \"你的R2端点URL\",${NC}"
    echo -e "            ${YELLOW}\"R2_ACCESS_KEY_ID\": \"你的R2 Access Key ID\",${NC}"
    echo -e "            ${YELLOW}\"R2_SECRET_ACCESS_KEY\": \"你的R2 Secret Access Key\",${NC}"
    echo -e "            ${YELLOW}\"R2_REGION\": \"auto\"${NC}"
    echo -e "          ${YELLOW}}${NC}"
    echo -e "        ${YELLOW}}${NC}"
    echo -e "      }"
    echo -e "    }"
    echo -e "  }"
    echo ""
}

# -----------------------------------------------------------------------------
# 完成提示
# -----------------------------------------------------------------------------

print_success() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║           安装完成!                      ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${INFO} Skill 路径: ${CYAN}${SKILL_DIR}${NC}"
    echo -e "  ${INFO} 配置文件:   ${CYAN}${CONFIG_FILE}${NC}"
    echo ""
    echo -e "  ${BOLD}下一步:${NC}"

    if [ "$SKIP_CONFIG" = true ]; then
        echo -e "  1. 按上方提示编辑 ${CYAN}${CONFIG_FILE}${NC} 添加配置"
        echo -e "  2. 重启 OpenClaw 服务"
        echo -e "  3. 发送一条语音消息测试"
    else
        echo -e "  1. 重启 OpenClaw 服务"
        echo -e "  2. 发送一条语音消息测试"
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# 主流程
# -----------------------------------------------------------------------------

TOTAL_STEPS=5

main() {
    print_banner
    check_prerequisites
    detect_install_path
    collect_config
    install_skill
    write_config
    print_success
}

main
