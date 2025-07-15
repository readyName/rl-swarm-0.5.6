#!/bin/bash

set -euo pipefail
export WANDB_MODE=disabled
export WANDB_MODE=offline
export WANDB_DISABLED=true
export WANDB_SILENT=true
export WANDB_CONSOLE=off

# 配置参数
RESTART_DELAY=30
CHECK_INTERVAL=10
PID_FILE="$HOME/training.pid"
MAX_RETRIES=1000000
WARNING_THRESHOLD=10
RETRY_COUNT=0

# ====== ✅ Log with timestamp ======
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 清理函数
cleanup() {
    # 主进程 PID
    if [ -f "$PID_FILE" ]; then
        MAIN_PID=$(cat "$PID_FILE")
        log "🧨 Main process PID: $MAIN_PID"
        if ps -p "$MAIN_PID" > /dev/null 2>&1; then
            log "🧨 Terminating main process PID: $MAIN_PID"
            kill -TERM "$MAIN_PID" 2>/dev/null || true
            sleep 5
            if ps -p "$MAIN_PID" > /dev/null 2>&1; then
                kill -KILL "$MAIN_PID" 2>/dev/null || true
            fi
        fi
        rm -f "$PID_FILE"
    else
        log "🧨 No main process PID file found."
    fi

    # Python 子进程 PID
    PYTHON_PIDS=$(pgrep -f "python.*run_rl_swarm" || true)
    if [ -n "$PYTHON_PIDS" ]; then
        log "🧨 Python subprocess PIDs: $PYTHON_PIDS"
        echo "$PYTHON_PIDS" | while read pid; do
            log "⚔️ Killing Python PID: $pid"
            kill -9 "$pid" 2>/dev/null || true
        done
    else
        log "🧨 No Python subprocesses found."
    fi

    # p2pd 进程 PID
    P2PD_PIDS=$(pgrep -x "p2pd" || true)
    if [ -n "$P2PD_PIDS" ]; then
        log "🔍 Residual p2pd process PIDs: $P2PD_PIDS"
        echo "$P2PD_PIDS" | while read pid; do
            log "⚔️ Killing p2

System: pd PID: $pid"
            kill -9 "$pid" 2>/dev/null || true
        done
        log "✅ p2pd processes terminated."
    else
        log "✅ No residual p2pd processes found."
    fi

    # 端口 3000 PID
    PORT_PID=$(lsof -ti:3000 || true)
    if [ -n "$PORT_PID" ]; then
        log "🌐 Port 3000 occupied by PID: $PORT_PID"
        log "⚠️ Releasing port 3000 PID: $PORT_PID"
        kill -9 "$PORT_PID" 2>/dev/null || true
        log "✅ Port 3000 released."
    else
        log "✅ Port 3000 is free."
    fi
    exit 0
}

# 捕获 Ctrl+C 和 SIGTERM 信号，自动清理
trap cleanup SIGINT SIGTERM

# 检查进程是否运行
is_process_running() {
    if [ -f "$PID_FILE" ]; then
        MAIN_PID=$(cat "$PID_FILE")
        if ps -p "$MAIN_PID" > /dev/null 2>&1; then
            return 0
        fi
    fi
    SWARM_PIDS=$(pgrep -f "swarm_launcher.py" || true)
    if [ -n "$SWARM_PIDS" ]; then
        return 0
    fi
    return 1
}

# 启动训练进程
start_training() {
    log "🚀 Attempt $((RETRY_COUNT + 1)): Starting RL Swarm..."
    #export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
    #export PYTORCH_ENABLE_MPS_FALLBACK=1
    ./run_rl_swarm.sh &
    MAIN_PID=$!
    log "✅ Main process started, PID: $MAIN_PID"
    echo "$MAIN_PID" > "$PID_FILE"
    sleep 15
    if ps -p "$MAIN_PID" > /dev/null 2>&1; then
        PYTHON_PIDS=$(pgrep -f "python.*run_rl_swarm" || true)
        if [ -n "$PYTHON_PIDS" ]; then
            log "✅ Python subprocess PIDs: $PYTHON_PIDS"
        else
            log "⚠️ No Python subprocesses found."
        fi
        return 0
    fi
    rm -f "$PID_FILE"
    log "⚠️ Main process $MAIN_PID not running. Likely failed to start."
    return 1
}

# 主监控循环
main() {
    if ! start_training; then
        log "🛑 Initial start failed. Exiting..."
        exit 1
    fi
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        sleep "$CHECK_INTERVAL"
        if ! is_process_running; then
            log "⚠️ Training process exited."
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -eq $WARNING_THRESHOLD ]; then
                log "🚨 Warning: RL Swarm has restarted $WARNING_THRESHOLD times. Check system health."
            fi
            log "🔄 Preparing restart $((RETRY_COUNT + 1)) after $RESTART_DELAY seconds..."
            # 清理残余进程和端口
            PYTHON_PIDS=$(pgrep -f "python.*run_rl_swarm" || true)
            if [ -n "$PYTHON_PIDS" ]; then
                log "🧨 Residual Python PIDs: $PYTHON_PIDS"
                echo "$PYTHON_PIDS" | while read pid; do
                    log "⚔️ Killing Python PID: $pid"
                    kill -9 "$pid" 2>/dev/null || true
                done
            else
                log "🧨 No residual Python processes found."
            fi
            P2PD_PIDS=$(pgrep -x "p2pd" || true)
            if [ -n "$P2PD_PIDS" ]; then
                log "🔍 Residual p2pd PIDs: $P2PD_PIDS"
                echo "$P2PD_PIDS" | while read pid; do
                    log "⚔️ Killing p2pd PID: $pid"
                    kill -9 "$pid" 2>/dev/null || true
                done
                log "✅ p2pd processes terminated."
            else
                log "✅ No residual p2pd processes found."
            fi
            PORT_PID=$(lsof -ti:3000 || true)
            if [ -n "$PORT_PID" ]; then
                log "🌐 Port 3000 occupied by PID: $PORT_PID"
                log "⚠️ Releasing port 3000 PID: $PORT_PID"
                kill -9 "$PORT_PID" 2>/dev/null || true
                log "✅ Port 3000 released."
            else
                log "✅ Port 3000 is free."
            fi
            sleep "$RESTART_DELAY"
            start_training
        fi
    done
    log "🛑 Maximum retry limit ($MAX_RETRIES) reached. Exiting..."
}

# 启动脚本
main
