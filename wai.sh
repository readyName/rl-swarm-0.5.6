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
    sysname="$(uname)"
    if [[ "$sysname" == "Darwin" ]]; then
        chip=$(sysctl -n machdep.cpu.brand_string)
        log "检测到 macOS，芯片信息：$chip"
        export OS_TYPE="macos"
    elif [[ "$sysname" == "Linux" ]]; then
        cpu=$(lscpu | grep 'Model name' | awk -F: '{print $2}' | xargs)
        log "检测到 Linux，CPU 型号：$cpu"
        export OS_TYPE="linux"
    else
        error "此脚本仅适用于 macOS 或 Ubuntu/Linux"
    fi
}

install_missing_dependencies() {
    log "检查并安装缺失依赖..."
    if [[ "$OS_TYPE" == "macos" ]]; then
        dependencies=("curl" "git" "wget" "jq" "python3" "node")
        if ! command -v brew >/dev/null 2>&1; then
            log "Homebrew 未安装，正在安装..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || error "Homebrew 安装失败"
            eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
        else
            log "Homebrew 已安装"
        fi
        for dep in "${dependencies[@]}"; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                log "安装 $dep ..."
                brew install "$dep" || error "$dep 安装失败"
            else
                log "$dep 已安装"
            fi
        done
    elif [[ "$OS_TYPE" == "linux" ]]; then
        dependencies=("curl" "git" "wget" "jq" "python3" "nodejs")
        if ! command -v apt-get >/dev/null 2>&1; then
            error "未检测到 apt-get，请确认你使用的是 Ubuntu 或 Debian 系统"
        fi
        sudo apt-get update
        for dep in "${dependencies[@]}"; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                log "安装 $dep ..."
                sudo apt-get install -y "$dep" || error "$dep 安装失败"
            else
                log "$dep 已安装"
            fi
        done
    fi
}

install_wai_cli() {
    if ! command -v wai >/dev/null 2>&1; then
        log "安装 WAI CLI..."
        curl -fsSL https://app.w.ai/install.sh | bash || error "WAI CLI 安装失败"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
        export PATH="$HOME/.local/bin:$PATH"
        log "WAI CLI 安装成功"
    else
        log "WAI CLI 已安装，版本：$(wai --version)"
    fi
}

configure_env() {
    BASH_CONFIG="$HOME/.bashrc"
    ZSH_CONFIG="$HOME/.zshrc"
    if grep -q "^export W_AI_API_KEY=" "$BASH_CONFIG" 2>/dev/null; then
        export W_AI_API_KEY=$(grep "^export W_AI_API_KEY=" "$BASH_CONFIG" | sed 's/.*=//;s/\"//g')
        log "已从 ~/.bashrc 加载 W_AI_API_KEY"
    elif grep -q "^export W_AI_API_KEY=" "$ZSH_CONFIG" 2>/dev/null; then
        export W_AI_API_KEY=$(grep "^export W_AI_API_KEY=" "$ZSH_CONFIG" | sed 's/.*=//;s/\"//g')
        log "已从 ~/.zshrc 加载 W_AI_API_KEY"
    else
        read -r -p "请输入你的 WAI API 密钥: " api_key
        [[ -z "$api_key" ]] && error "W_AI_API_KEY 不能为空"
        echo "export W_AI_API_KEY=\"$api_key\"" >> "$BASH_CONFIG"
        echo "export W_AI_API_KEY=\"$api_key\"" >> "$ZSH_CONFIG"
        export W_AI_API_KEY="$api_key"
        log "W_AI_API_KEY 已保存并加载"
    fi
}

run_wai_worker() {
    WAI_CMD="$HOME/.local/bin/wai"
    RETRY=1

    log "启动 WAI Worker..."

    while true; do
        log "🔁 准备开始新一轮挖矿..."

        if pgrep -f "[p]ython -m model.main" >/dev/null; then
            pkill -9 -f "[p]ython -m model.main"
            log "✅ 清理旧进程"
        else
            log "✅ 无旧进程"
        fi

        log "🚀 启动 Worker，运行 5 分钟..."
        env POSTHOG_DISABLED=true "$WAI_CMD" run &
        WAI_PID=$!
        sleep 300 &
        SLEEP_PID=$!

        elapsed=0
        while [ $elapsed -lt 300 ]; do
            if ! kill -0 $WAI_PID 2>/dev/null; then
                wait $WAI_PID
                EXIT_CODE=$?
                break
            fi
            sleep 1
            ((elapsed++))
        done

        if kill -0 $WAI_PID 2>/dev/null; then
            log "⏰ 超时，重启 Worker..."
            kill -9 $WAI_PID
            RETRY=1
            sleep 10
        elif [ $EXIT_CODE -ne 0 ]; then
            warn "⚠️ Worker 异常退出（代码 $EXIT_CODE），10 秒后重试..."
            sleep 10
            RETRY=$(( RETRY < 8 ? RETRY+1 : 8 ))
        else
            log "✅ 正常退出，重置重试计数"
            RETRY=1
            sleep 10
        fi

        kill -0 $SLEEP_PID 2>/dev/null && kill -9 $SLEEP_PID
    done
}

main() {
    check_system
    install_missing_dependencies
    install_wai_cli
    configure_env
    log "✅ 所有准备就绪，启动 Worker..."
    run_wai_worker
}

main
