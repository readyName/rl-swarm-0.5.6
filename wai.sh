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
        install_commands=("brew install curl" "brew install git" "brew install wget" "brew install jq" "brew install python" "brew install node")
        if ! command -v brew >/dev/null 2>&1; then
            log "Homebrew 未安装，正在安装 Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            if [[ $? -ne 0 ]]; then
                error "Homebrew 安装失败，请手动安装 Homebrew 后重试"
            fi
            if [[ "$(uname -m)" == "arm64" ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            else
                eval "$(/usr/local/bin/brew shellenv)"
            fi
        else
            log "Homebrew 已安装"
        fi
        for ((i=0; i<${#dependencies[@]}; i++)); do
            dep=${dependencies[$i]}
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
    elif [[ "$OS_TYPE" == "linux" ]]; then
        dependencies=("curl" "git" "wget" "jq" "python3" "nodejs")
        install_commands=("apt-get install -y curl" "apt-get install -y git" "apt-get install -y wget" "apt-get install -y jq" "apt-get install -y python3" "apt-get install -y nodejs")
        if ! command -v apt-get >/dev/null 2>&1; then
            error "未检测到 apt-get，请确认你使用的是 Ubuntu 或 Debian 系统"
        fi
        sudo apt-get update
        for ((i=0; i<${#dependencies[@]}; i++)); do
            dep=${dependencies[$i]}
            install_cmd=${install_commands[$i]}
            log "检查 ${dep}..."
            if ! command -v "${dep}" >/dev/null 2>&1; then
                log "${dep} 未找到，尝试安装..."
                sudo ${install_cmd}
                if [[ $? -eq 0 ]]; then
                    log "${dep} 安装成功"
                else
                    error "${dep} 安装失败，请手动安装"
                fi
            else
                log "${dep} 已安装"
            fi
        done
    fi
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
    BASH_CONFIG_FILE="$HOME/.bashrc"
    ZSH_CONFIG_FILE="$HOME/.zshrc"
    if grep -q "^export W_AI_API_KEY=" "$BASH_CONFIG_FILE" 2>/dev/null; then
        export W_AI_API_KEY=$(grep "^export W_AI_API_KEY=" "$BASH_CONFIG_FILE" | sed 's/.*=//;s/\"//g')
        log "检测到 W_AI_API_KEY，已从 ~/.bashrc 加载"
    elif grep -q "^export W_AI_API_KEY=" "$ZSH_CONFIG_FILE" 2>/dev/null; then
        export W_AI_API_KEY=$(grep "^export W_AI_API_KEY=" "$ZSH_CONFIG_FILE" | sed 's/.*=//;s/\"//g')
        log "检测到 W_AI_API_KEY，已从 ~/.zshrc 加载"
    else
        read -r -p "请输入你的 WAI API 密钥: " api_key
        if [[ -z "$api_key" ]]; then
            error "W_AI_API_KEY 不能为空"
        fi
        echo "export W_AI_API_KEY=\"$api_key\"" >> "$BASH_CONFIG_FILE"
        echo "export W_AI_API_KEY=\"$api_key\"" >> "$ZSH_CONFIG_FILE"
        export W_AI_API_KEY="$api_key"
        log "W_AI_API_KEY 已写入 ~/.bashrc 和 ~/.zshrc 并加载"
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

        log "✅ 启动 Worker（限时5分钟）..."
        # 10分钟后自动终止并重启，遇到错误也立即重启
        timeout 300 POSTHOG_DISABLED=true "$WAI_CMD" run
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            log "⏰ Worker 已运行5分钟，自动重启..."
            RETRY=1
            sleep 10
        elif [ $EXIT_CODE -ne 0 ]; then
            warn "⚠️ Worker 异常退出（退出码 $EXIT_CODE），等待 10 秒后重试..."
            sleep 10
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
