#!/bin/bash
set -euo pipefail

# 配置参数
export WANDB_MODE=disabled  # 完全禁用 W&B
RESTART_DELAY=30           # 重启延迟时间（秒）
CHECK_INTERVAL=10          # 检查间隔时间（秒）
LOG_FILE="/home/gensyn/rl_swarm/logs/auto_monitor.log"  # 日志文件路径
PID_FILE="/home/gensyn/rl_swarm/training.pid"           # 进程 PID 文件路径
MAX_RETRIES=1000000        # 最大重试次数
WARNING_THRESHOLD=10       # 警告阈值

# 颜色输出设置
GREEN="\033[32m"           # 绿色，用于成功信息
BLUE="\033[34m"            # 蓝色，用于普通信息
RED="\033[31m"             # 红色，用于错误信息
YELLOW="\033[33m"          # 黄色，用于警告信息
RESET="\033[0m"            # 重置颜色

# 检查日志文件路径是否可写
check_log_file() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if ! mkdir -p "$log_dir" 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
        stdbuf -oL echo -e "${RED}❌ 日志文件路径 $LOG_FILE 不可写，仅输出到终端${RESET}"
        LOG_FILE="/dev/null"
    fi
}

# 重要信息日志（同时输出到终端和日志文件，非缓冲）
log_important() {
    stdbuf -oL echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 颜色输出函数
echo_green() { stdbuf -oL echo -e "${GREEN}$1${RESET}" | tee -a "$LOG_FILE"; }
echo_blue() { stdbuf -oL echo -e "${BLUE}$1${RESET}" | tee -a "$LOG_FILE"; }
echo_red() { stdbuf -oL echo -e "${RED}$1${RESET}" | tee -a "$LOG_FILE"; log_important "$1"; }
echo_yellow() { stdbuf -oL echo -e "${YELLOW}$1${RESET}" | tee -a "$LOG_FILE"; log_important "$1"; }

# 清理函数：处理脚本退出时的清理工作
cleanup() {
    echo_yellow "🛑 清理"
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo_yellow "终止 run_rl_swarm.sh 进程 PID: $pid"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 5
            if ps -p "$pid" > /dev/null 2>&1; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$PID_FILE"
    fi
    # 清理所有 swarm_launcher 进程
    pgrep -f "python.*rgym_exp.runner.swarm_launcher" | while read pid; do
        echo_yellow "终止 Python PID: $pid"
        kill -9 "$pid" || true
    done
    pkill -f "p2pd" 2>/dev/null || true
    pkill -f "yarn start" 2>/dev/null || true
    echo_green "✅ 已停止"
    exit 0
}

# 检查进程是否运行
is_process_running() {
    local py_pids
    py_pids=$(pgrep -f "python.*rgym_exp.runner.swarm_launcher")
    if [ -n "$py_pids" ]; then
        echo "$py_pids" > "$PID_FILE"
        return 0  # swarm_launcher 进程存在
    fi
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0  # run_rl_swarm.sh 进程存在
        fi
    fi
    return 1  # 进程不存在
}

# 启动训练进程
start_training() {
    echo_blue "🚀 启动 RL Swarm 训练 (Docker 环境)..."

    # 设置环境变量（合并两个脚本的环境变量）
    export OMP_NUM_THREADS=8
    export MKL_NUM_THREADS=8
    export CPU_ONLY=1
    export HF_HUB_DOWNLOAD_TIMEOUT=300
    export HF_DATASETS_CACHE="/home/gensyn/rl_swarm/.cache/huggingface/datasets"
    export HF_MODELS_CACHE="/home/gensyn/rl_swarm/.cache/huggingface/transformers"

    # 确保缓存目录存在并设置权限
    mkdir -p "$HF_DATASETS_CACHE" "$HF_MODELS_CACHE"
    chmod -R 777 "$HF_DATASETS_CACHE" "$HF_MODELS_CACHE"

    # 清理残留 p2pd 进程
    if pgrep -x "p2pd" >/dev/null 2>&1; then
        echo_yellow "🔍 Found residual p2pd process, terminating..."
        pkill -9 p2pd
        echo_green "✅ p2pd process terminated."
    fi

    # 清理残留 Python 进程
    echo_yellow "🧨 Cleaning up residual Python processes..."
    pgrep -f "python.*rgym_exp.runner.swarm_launcher" | while read pid; do
        echo_yellow "⚔️ Killing Python PID: $pid"
        kill -9 "$pid" || true
    done

    # 检查并释放端口 3000
    echo_blue "🌐 Checking port 3000 status..."
    PORT_PID=$(lsof -ti:3000)
    if [ -n "$PORT_PID" ]; then
        echo_yellow "⚠️ Port 3000 is occupied by PID $PORT_PID. Releasing..."
        kill -9 "$PORT_PID"
        echo_green "✅ Port 3000 released."
    else
        echo_green "✅ Port 3000 is free."
    fi

    # 启动 run_rl_swarm.sh，最多重试 3 次
    for i in {1..3}; do
        stdbuf -oL ./run_rl_swarm.sh 2>&1 | tee -a "$LOG_FILE" &
        local pid=$!
        echo "$pid" > "$PID_FILE"
        echo_green "✅ run_rl_swarm.sh started, PID: $pid"
        sleep 15
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0  # 启动成功
        fi
        echo_red "❌ run_rl_swarm.sh startup failed, retry $i/3"
        rm -f "$PID_FILE"
        sleep 5
    done
    echo_red "❌ run_rl_swarm.sh startup failed, reached max retries"
    return 1
}

# 信号处理：捕获 SIGINT 和 SIGTERM
trap cleanup SIGINT SIGTERM

# 主监控循环
main() {
    # 检查日志文件路径
    check_log_file
    echo_green "🎯 RL Swarm 自动监控启动 (Docker 环境)"
    echo_blue "⏱️ 检查间隔: ${CHECK_INTERVAL}秒"
    echo_blue "⏰ 重启延迟: ${RESTART_DELAY}秒"
    echo_blue "📜 日志文件: $LOG_FILE"
    echo ""

    local restart_count=0
    if ! start_training; then
        echo_red "❌ 初始启动失败"
        exit 1
    fi

    while [ $restart_count -lt $MAX_RETRIES ]; do
        sleep "$CHECK_INTERVAL"

        # 检查 swarm_launcher 进程
        PY_PIDS=$(pgrep -f "python.*rgym_exp.runner.swarm_launcher")
        PY_PID_COUNT=$(echo "$PY_PIDS" | wc -w)
        if [ "$PY_PID_COUNT" -gt 1 ]; then
            echo_yellow "🚨 Warning: Detected $PY_PID_COUNT identical swarm_launcher processes, PIDs: $PY_PIDS"
            echo_yellow "ℹ️ All swarm_launcher processes:"
            ps -eo pid,ppid,cmd | grep "python.*rgym_exp.runner.swarm_launcher" | grep -v grep >> "$LOG_FILE"
        fi

        if ! is_process_running; then
            echo_yellow "⚠️ 检测到训练进程已结束"
            restart_count=$((restart_count + 1))
            echo_yellow "🔄 准备第 $restart_count 次重启"

            # 检查内存使用
            MEMORY_USAGE=$(docker stats --no-stream --format "{{.MemUsage}}" swarm-cpu | head -n 1)
            echo_blue "ℹ️ Container swarm-cpu memory usage: $MEMORY_USAGE"
            if [[ "$MEMORY_USAGE" =~ "GiB" && $(echo "$MEMORY_USAGE" | grep -o "[0-9.]*") > 3.5 ]]; then
                echo_yellow "🚨 Warning: High memory usage detected, may cause process termination."
            fi

            # 捕获容器日志
            echo_yellow "ℹ️ Capturing last 20 lines of container logs..."
            docker-compose logs swarm-cpu | tail -n 20 >> "$LOG_FILE"

            # 检查容器状态
            if ! docker-compose ps | grep swarm-cpu | grep -q "Up"; then
                echo_red "🚨 Container swarm-cpu stopped, exiting loop to restart container..."
                break
            fi

            echo_yellow "⏰ 等待 $RESTART_DELAY 秒后重启..."
            sleep "$RESTART_DELAY"
            if start_training; then
                echo_green "✅ 第 $restart_count 次重启成功"
            else
                echo_red "❌ 第 $restart_count 次重启失败，将继续尝试"
            fi
        fi

        if [ $restart_count -eq $WARNING_THRESHOLD ]; then
            echo_yellow "🚨 Warning: RL Swarm has restarted $WARNING_THRESHOLD times. Check system health."
            echo_yellow "ℹ️ Capturing last 20 lines of container logs..."
            docker-compose logs swarm-cpu | tail -n 20 >> "$LOG_FILE"
        fi
    done

    echo_red "🛑 Maximum retry limit ($MAX_RETRIES) reached. Exiting..."
    cleanup
}

# 启动脚本
main
