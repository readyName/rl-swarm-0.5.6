#!/bin/bash

set -euo pipefail

# 配置参数
RESTART_DELAY=30                  # 重启延迟时间（秒）
CHECK_INTERVAL=10                 # 检查间隔时间（秒）
LOG_FILE="/home/gensyn/rl_swarm/logs/auto_monitor.log"  # 日志文件路径
PID_FILE="/home/gensyn/rl_swarm/training.pid"           # 进程 PID 文件路径

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
    stdbuf -oL echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ====== 🔁 Start daemon loop ======
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  log "🚀 Attempt $((RETRY_COUNT + 1)): Starting RL Swarm..."

  # ✅ Set MPS environment (for Mac M1/M2 if applicable)
  #export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
  #export PYTORCH_ENABLE_MPS_FALLBACK=1
  source ~/.zshrc

  # ✅ Kill lingering p2pd process if exists
  if pgrep -x "p2pd" >/dev/null; then
    log "🔍 Found residual p2pd process, terminating..."
    pkill -9 p2pd
    log "✅ p2pd process terminated."
  fi

  # ✅ Start main script in background with automated input
  log "✅ Providing automated input:Y, A, 0.5, N"
  echo -e "" | ./run_rl_swarm.sh &
  RL_PID=$!

  # ✅ Wait for Python child process to initialize
  sleep 600
  PY_PID=$(pgrep -P $RL_PID -f python | head -n 1)

  if [ -z "$PY_PID" ]; then
    log "⚠️ No Python subprocess found. Likely failed to start."
  else
    log "✅ Python subprocess detected. PID: $PY_PID"
  fi

  # ✅ Monitor the subprocess
  while kill -0 $PY_PID >/dev/null 2>&1; do
    sleep 2
  done

  # ✅ Cleanup and prepare for restart
  log "⚠️ Python subprocess exited. Restarting..."

  # 🧨 Kill residual Python processes
  log "🧨 Cleaning up residual Python processes..."
  pgrep -f "python.*run_rl_swarm" | while read pid; do
    log "⚔️ Killing Python PID: $pid"
    kill -9 "$pid"
  done

  # 🌐 Check and free port 3000 if occupied
  log "🌐 Checking port 3000 status..."
  PORT_PID=$(lsof -ti:3000)
  if [ -n "$PORT_PID" ]; then
    log "⚠️ Port 3000 is occupied by PID $PORT_PID. Releasing..."
    kill -9 $PORT_PID
    log "✅ Port 3000 released."
  else
    log "✅ Port 3000 is free."
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))

  if [ $RETRY_COUNT -eq $WARNING_THRESHOLD ]; then
    log "🚨 Warning: RL Swarm has restarted $WARNING_THRESHOLD times. Check system health."
  fi

  sleep 2
done

# ❌ Exceeded max retries
log "🛑 Maximum retry limit ($MAX_RETRIES) reached. Exiting..."
# ❌ 达到最大重试次数
log "🛑 已达到最大重试次数 ($MAX_RETRIES)，程序退出"
