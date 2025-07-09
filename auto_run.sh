#!/bin/bash

set -euo pipefail

# 检测当前操作系统
detect_os() {
    OS=$(uname -s)
    case "$OS" in
        Darwin)
            echo "macOS"
            USER_HOME="/Users/$USER"
            ;;
        Linux)
            if grep -qi "microsoft" /proc/version 2>/dev/null; then
                echo "WSL"
                USER_HOME="$HOME"
            else
                echo "Ubuntu"
                USER_HOME="$HOME"
            fi
            ;;
        *)
            echo "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# 设置路径根据操作系统
OS_TYPE=$(detect_os)
BASE_DIR="$USER_HOME/rl-swarm-0.5.3"
LOG_FILE="$BASE_DIR/logs/auto_monitor.log"  # 日志文件路径
PID_FILE="$BASE_DIR/training.pid"           # 进程 PID 文件路径
HF_DATASETS_CACHE="$BASE_DIR/.cache/huggingface/datasets"
HF_MODELS_CACHE="$BASE_DIR/.cache/huggingface/transformers"

# 配置参数
RESTART_DELAY=30                  # 重启延迟时间（秒）
CHECK_INTERVAL=10                 # 检查间隔时间（秒）

# 默认参数配置
DEFAULT_HF_PUSH="N"               # 默认不推送模型到 Hugging Face
DEFAULT_MODEL_NAME="Gensyn/Qwen2.5-0.5B-Instruct"  # 默认模型名称

# 颜色输出设置
GREEN="\033[32m"                  # 绿色，用于成功信息
BLUE="\033[34m"                   # 蓝色，用于普通信息
RED="\033[31m"                    # 红色，用于错误信息
YELLOW="\033[33m"                 # 黄色，用于警告信息
RESET="\033[0m"                   # 重置颜色

# 检查日志文件路径是否可写
check_log_file() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if ! mkdir -p "$log_dir" 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
        echo -e "${RED}❌ 日志文件路径 $LOG_FILE 不可写，仅输出到终端${RESET}"
        LOG_FILE="/dev/null"  # 如果不可写，仅输出到终端
    fi
}

# 重要信息日志（同时输出到终端和日志文件，非缓冲）
log_important() {
    if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    fi
}

# 颜色输出函数（兼容没有 stdbuf 的环境）
echo_green() {
    if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL echo -e "${GREEN}$1${RESET}" | tee -a "$LOG_FILE"
    else
        echo -e "${GREEN}$1${RESET}" | tee -a "$LOG_FILE"
    fi
}
echo_blue() {
    if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL echo -e "${BLUE}$1${RESET}" | tee -a "$LOG_FILE"
    else
        echo -e "${BLUE}$1${RESET}" | tee -a "$LOG_FILE"
    fi
}
echo_red() {
    if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL echo -e "${RED}$1${RESET}" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}$1${RESET}" | tee -a "$LOG_FILE"
    fi
    log_important "$1"
}
echo_yellow() {
    if command -v stdbuf >/dev/null 2>&1; then
        stdbuf -oL echo -e "${YELLOW}$1${RESET}" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}$1${RESET}" | tee -a "$LOG_FILE"
    fi
    log_important "$1"
}

# 清理函数：处理脚本退出时的清理工作
cleanup() {
    echo_yellow "🛑 清理"
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo_yellow "终止训练进程 PID: $pid"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 5
            if ps -p "$pid" > /dev/null 2>&1; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$PID_FILE"
    fi
    pkill -f "swarm_launcher.py" 2>/dev/null || true
    pkill -f "run_rl_swarm.sh" 2>/dev/null || true
    pkill -f "yarn start" 2>/dev/null || true
    echo_green "✅ 已停止"
    exit 0
}

# 检查进程是否运行
is_process_running() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0  # 进程存在
        fi
    fi
    if pgrep -f "swarm_launcher.py" > /dev/null 2>&1; then
        return 0  # swarm_launcher.py 进程存在
    fi
    return 1  # 进程不存在
}

# 启动训练进程
start_training() {
    echo_blue "🚀 启动 RL Swarm 训练 ..."
    
    # 设置环境变量
    export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
    export OMP_NUM_THREADS=8
    export MKL_NUM_THREADS=8
    if [ "$OS_TYPE" = "macOS" ]; then
        export PYTORCH_ENABLE_MPS_FALLBACK=1
        export CPU_ONLY=0
    else
        export PYTORCH_ENABLE_MPS_FALLBACK=0
        export CPU_ONLY=1  # Linux/WSL 默认使用 CPU
    fi
    export HF_HUB_DOWNLOAD_TIMEOUT=500
    export HF_DATASETS_CACHE="$HF_DATASETS_CACHE"
    export HF_MODELS_CACHE="$HF_MODELS_CACHE"
    export CONNECT_TO_TESTNET=true
    export SWARM_CONTRACT="0xFaD7C5e93f28257429569B854151A1B8DCD404c2"
    export HUGGINGFACE_ACCESS_TOKEN="None"
    export MODEL_NAME="$DEFAULT_MODEL_NAME"
    export IDENTITY_PATH="$BASE_DIR/keys/swarm.pem"
    export GENSYN_RESET_CONFIG=""
    
    # 确保缓存目录存在并设置权限
    mkdir -p "$HF_DATASETS_CACHE" "$HF_MODELS_CACHE" "$BASE_DIR/keys" "$BASE_DIR/logs"
    chmod -R 777 "$HF_DATASETS_CACHE" "$HF_MODELS_CACHE" "$BASE_DIR/keys" "$BASE_DIR/logs"
    
    # 尝试启动 run_rl_swarm.sh，最多重试 3 次
    for i in {1..3}; do
        if [ -f "./run_rl_swarm.sh" ]; then
            if command -v stdbuf >/dev/null 2>&1; then
                stdbuf -oL ./run_rl_swarm.sh 2>&1 | tee -a "$LOG_FILE" &
            else
                ./run_rl_swarm.sh 2>&1 | tee -a "$LOG_FILE" &
            fi
            local pid=$!
            echo "$pid" > "$PID_FILE"
            echo_green "✅ 训练进程已启动，PID: $pid"
            sleep 15
            if ps -p "$pid" > /dev/null 2>&1; then
                return 0  # 启动成功
            fi
            echo_red "❌ 训练进程启动失败，重试 $i/3"
            rm -f "$PID_FILE"
            sleep 5
        else
            echo_red "❌ run_rl_swarm.sh 文件不存在"
            return 1
        fi
    done
    echo_red "❌ 训练进程启动失败，达到最大重试次数"
    return 1
}

# 信号处理：捕获 SIGINT 和 SIGTERM 信号以进行清理
trap cleanup SIGINT SIGTERM

# 主监控循环
main() {
    # 检查日志文件路径
    check_log_file
    
    local restart_count=0
    echo_green "🎯 RL Swarm 自动监控启动 ($OS_TYPE 环境)"
    echo_blue "⏱️ 检查间隔: ${CHECK_INTERVAL}秒"
    echo_blue "⏰ 重启延迟: ${RESTART_DELAY}秒"
    echo ""
    if ! start_training; then
        echo_red "❌ 初始启动失败"
        exit 1
    fi
    while true; do
        sleep "$CHECK_INTERVAL"
        if ! is_process_running; then
            echo_yellow "⚠️ 检测到训练进程已结束"
            restart_count=$((restart_count + 1))
            echo_yellow "🔄 准备第 $restart_count 次重启"
            echo_yellow "⏰ 等待 $RESTART_DELAY 秒后重启..."
            sleep "$RESTART_DELAY"
            if start_training; then
                echo_green "✅ 第 $restart_count 次重启成功"
            else
                echo_red "❌ 第 $restart_count 次重启失败，将继续尝试"
            fi
        fi
    done
}

# 启动脚本
main