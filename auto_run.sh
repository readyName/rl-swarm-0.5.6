#!/bin/bash

set -euo pipefail

# 配置参数
RESTART_DELAY=30                  # 重启延迟时间（秒）
CHECK_INTERVAL=10                 # 检查间隔时间（秒）
WARNING_THRESHOLD=10              # 警告阈值
LOG_FILE="/home/gensyn/rl_swarm/logs/auto_monitor.log"  # 日志文件路径
PID_FILE="/home/gensyn/rl_swarm/training.pid"           # 进程 PID 文件路径

# 颜色输出设置
GREEN="\033[32m"  # 绿色：成功
BLUE="\033[34m"   # 蓝色：普通信息
RED="\033[31m"    # 红色：错误
YELLOW="\033[33m" # 黄色：警告
RESET="\033[0m"   # 重置颜色

# 日志函数：带时间戳，输出到终端和日志文件
log() {
    stdbuf -oL echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 带颜色的日志输出
log_green() { log "${GREEN}$1${RESET}"; }
log_blue() { log "${BLUE}$1${RESET}"; }
log_red() { log "${RED}$1${RESET}"; }
log_yellow() { log "${YELLOW}$1${RESET}"; }

# 检查日志文件路径是否可写
check_log_file() {
    local log_dir=$(dirname "$LOG_FILE")
    if ! mkdir -p "$log_dir" 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
        log_red "❌ 日志文件路径 $LOG_FILE 不可写，仅输出到终端"
        LOG_FILE="/dev/null"
    fi
}

# 清理函数：处理退出时的清理工作
cleanup() {
    log_yellow "🛑 清理进程并退出"
    # 终止主进程
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" >/dev/null 2>&1; then
            log_yellow "终止主进程 PID: $pid"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 5
            if ps -p "$pid" >/dev/null 2>&1; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$PID_FILE"
    fi
    # 清理相关进程
    pkill -f "swarm_launcher.py" 2>/dev/null || true
    pkill -f "run_rl_swarm.sh" 2>/dev/null || true
    pkill -f "yarn start" 2>/dev/null || true
    pkill -f "p2pd" 2>/dev/null || true
    # 释放端口 3000
    local port_pid=$(lsof -ti:3000)
    if [ -n "$port_pid" ]; then
        log_yellow "释放端口 3000 (PID: $port_pid)"
        kill -9 "$port_pid" 2>/dev/null || true
    fi
    log_green "✅ 清理完成，退出脚本"
    exit 0
}

# 检查进程是否运行
is_process_running() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" >/dev/null 2>&1; then
            return 0
        fi
    fi
    if pgrep -f "swarm_launcher.py" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# 启动训练进程
start_training() {
    log_blue "🚀 启动 RL Swarm 训练..."
    # 设置环境变量
    export WANDB_MODE=offline
    # 确保缓存目录存在并设置权限
    mkdir -p "$HF_DATASETS_CACHE" "$HF_MODELS_CACHE"
    chmod -R 777 "$HF_DATASETS_CACHE" "$HF_MODELS_CACHE"
    
    # 提供自动化输入并启动
    for i in {1..3}; do
        log_blue "尝试启动 (第 $i/3 次)..."
        echo -e "Y\nA\n0.5\nN\n3" | ./run_rl_swarm.sh 2>&1 | tee -a "$LOG_FILE" &
        local pid=$!
        echo "$pid" > "$PID_FILE"
        log_green "✅ 训练进程启动，PID: $pid"
        sleep 15
        if ps -p "$pid" >/dev/null 2>&1; then
            # 检查 Python 子进程
            local py_pid=$(pgrep -P "$pid" -f python | head -n 1)
            if [ -n "$py_pid" ]; then
                log_green "✅ Python 子进程启动，PID: $py_pid"
                return 0
            else
                log_red "❌ 未检测到 Python 子进程"
            fi
        fi
        log_red "❌ 启动失败，重试 $i/3"
        rm -f "$PID_FILE"
        sleep 5
    done
    log_red "❌ 训练进程启动失败，达到最大重试次数"
    return 1
}

# 信号处理
trap cleanup SIGINT SIGTERM

# 主监控循环
main() {
    check_log_file
    local retry_count=0
    log_green "🎯 RL Swarm 自动监控启动"
    log_blue "⏱️ 检查间隔: ${CHECK_INTERVAL}秒 | 重启延迟: ${RESTART_DELAY}秒 | 无限重试"
    
    if ! start_training; then
        log_red "❌ 初始启动失败，将无限重试"
    fi
    
    while true; do
        sleep "$CHECK_INTERVAL"
        if ! is_process_running; then
            retry_count=$((retry_count + 1))
            log_yellow "⚠️ 训练进程已停止，第 $retry_count 次重启"
            if [ $retry_count -eq $WARNING_THRESHOLD ]; then
                log_red "🚨 警告：已重启 $WARNING_THRESHOLD 次，请检查系统状态"
            fi
            log_yellow "⏰ 等待 $RESTART_DELAY 秒后重启..."
            sleep "$RESTART_DELAY"
            if start_training; then
                log_green "✅ 第 $retry_count 次重启成功"
            else
                log_red "❌ 第 $retry_count 次重启失败，继续尝试"
            fi
        fi
    done
}

# 启动脚本
main
