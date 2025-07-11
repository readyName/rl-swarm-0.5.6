#!/bin/bash

# WAI Protocol 部署脚本
# 功能：安装依赖、配置环境变量、运行 WAI Worker 并自动重启，日志输出到终端

# ANSI 颜色代码
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1${NC}"; }
error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1${NC}"; exit 1; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1${NC}"; }

check_system() {
    log "检查系统..."
    if [[ "$(uname)" != "Darwin" ]]; then
        error "此脚本仅适用于 macOS"
    fi
    chip=$(sysctl -n machdep.cpu.brand_string)
    if [[ ! "$chip" =~ "Apple M" ]]; then
        warn "未检测到 Apple M 系列芯片，当前为：$chip"
    else
        log "Apple 芯片：$chip"
    fi
}

install_missing_dependencies() {
    log "检查并安装缺失依赖..."

    # 定义依赖及其检查/安装命令
    dependencies=("curl" "git" "wget" "jq" "python3" "node")
    commands=("curl --version" "git --version" "wget --version" "jq --version" "python3 --version" "node -v")
    install_commands=("brew install curl" "brew install git" "brew install wget" "brew install jq" "brew install python" "brew install node")

    # 确保 Homebrew 已安装
    if ! command -v brew >/dev/null 2>&1; then
        log "Homebrew 未安装，正在安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [[ $? -ne 0 ]]; then
            error "Homebrew 安装失败，请手动安装 Homebrew 后重试"
        fi
        # 根据架构更新 Homebrew PATH
        if [[ "$(uname -m)" == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    else
        log "Homebrew 已安装"
    fi

    # 检查并安装依赖
    for ((i=0; i<${#dependencies[@]}; i++)); do
        dep=${dependencies[$i]}
        cmd=${commands[$i]}
        install_cmd=${install_commands[$i]}

        log "检查 ${dep}..."
        if ! command -v "${dep}" >/dev/null 2>&1; then
            log "${dep} 未找到，尝试安装..."
            eval "${install_cmd}"
            if [[ $? -eq 0 ]]; then
                log "${dep} 安装成功"
            else
                error "${dep} 安装失败，请手动安装"
            fi
        else
            log "${dep} 已安装"
        fi
    done
}

install_wai_cli() {
    if ! command -v wai >/dev/null 2>&1; then
        log "安装 WAI CLI..."
        curl -fsSL https://app.w.ai/install.sh | bash
        if [[ $? -ne 0 ]]; then
            error "WAI CLI 安装失败，请检查网络或手动安装"
        fi
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
        export PATH="$HOME/.local/bin:$PATH"
        log "WAI CLI 安装成功"
    else
        log "WAI CLI 已安装，版本：$(wai --version)"
    fi
}

configure_env() {
    # 从 ~/.zshrc 读取 W_AI_API_KEY
    ZSH_CONFIG_FILE="$HOME/.zshrc"
    if grep -q "^export W_AI_API_KEY=" "$ZSH_CONFIG_FILE"; then
        export W_AI_API_KEY=$(grep "^export W_AI_API_KEY=" "$ZSH_CONFIG_FILE" | sed 's/.*=//;s/"//g')
        log "检测到 W_AI_API_KEY，已从 ~/.zshrc 加载"
    else
        read -r -p "请输入你的 WAI API 密钥: " api_key
        if [[ -z "$api_key" ]]; then
            error "W_AI_API_KEY 不能为空"
        fi
        echo "export W_AI_API_KEY=\"$api_key\"" >> "$ZSH_CONFIG_FILE"
        export W_AI_API_KEY="$api_key"
        log "W_AI_API_KEY 已写入 ~/.zshrc 并加载"
    fi
}

run_wai_worker() {
    WAI_CMD="$HOME/.local/bin/wai"
    RETRY=1

    log "开始运行 WAI Worker..."

    while true; do
        log "🔁 准备开始新一轮挖矿..."

        log "🧹 清理旧进程..."
        if pgrep -f "[p]ython -m model.main" >/dev/null; then
            pkill -9 -f "[p]ython -m model.main" 2>/dev/null
            log "✅ 旧进程清理完成"
        else
            log "✅ 无旧进程需要清理"
        fi

        log "✅ 启动 Worker..."
        # 运行 wai run 并捕获退出码
        POSTHOG_DISABLED=true "$WAI_CMD" run &
        WAI_PID=$!
        wait $WAI_PID
        EXIT_CODE=$?

        log "Worker 退出，退出码：$EXIT_CODE"
        if [ $EXIT_CODE -ne 0 ]; then
            warn "⚠️ Worker 异常退出（退出码 $EXIT_CODE），等待 $((RETRY*30)) 秒后重试..."
            sleep $((RETRY*30))
            RETRY=$(( RETRY < 8 ? RETRY+1 : 8 ))
        else
            log "✅ Worker 正常退出，重置重试计数"
            RETRY=1
            sleep 10
        fi
    done
}

main() {
    check_system
    install_missing_dependencies
    install_wai_cli
    configure_env
    log "所有依赖和配置已完成，启动 WAI Worker..."
    run_wai_worker
}

main