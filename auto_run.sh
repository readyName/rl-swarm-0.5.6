#!/bin/bash

export WANDB_MODE=disabled
export WANDB_MODE=offline
export WANDB_DISABLED=true
export WANDB_SILENT=true
export WANDB_CONSOLE=off


MAX_RETRIES=1000000
WARNING_THRESHOLD=10
RETRY_COUNT=0

# ====== 📝 带时间戳的日志函数 ======
log() {
  echo "【📅 $(date '+%Y-%m-%d %H:%M:%S')】 $1"
}

# ====== 🛑 处理 Ctrl+C 退出信号 ======
cleanup() {
  local mode=$1  # "exit" 或 "restart"
  log "🛑 触发清理流程（模式: $mode）..."
  # 杀主进程
  if [ -n "$RL_PID" ] && kill -0 "$RL_PID" 2>/dev/null; then
    log "🧨 杀死主进程 PID: $RL_PID"
    kill -9 "$RL_PID" 2>/dev/null
  fi
  # 杀子进程
  if [ -n "$PY_PID" ] && kill -0 "$PY_PID" 2>/dev/null; then
    log "⚔️ 杀死 Python 子进程 PID: $PY_PID"
    kill -9 "$PY_PID" 2>/dev/null
  fi
  # 释放端口 3000
  log "🌐 检查并释放端口 3000..."
  PORT_PID=$(lsof -ti:3000)
  if [ -n "$PORT_PID" ]; then
    log "⚠️ 端口 3000 被 PID $PORT_PID 占用，正在释放..."
    kill -9 "$PORT_PID" 2>/dev/null
    log "✅ 端口 3000 已释放"
  else
    log "✅ 端口 3000 已空闲"
  fi
  # 清理所有相关 python 进程
  log "🧨 清理所有相关 python 进程..."
  pgrep -f "python.*swarm_launcher" | while read pid; do
    log "⚔️ 杀死 python.swarm_launcher 进程 PID: $pid"
    kill -9 "$pid" 2>/dev/null || true
  done
  pgrep -f "python.*run_rl_swarm" | while read pid; do
    log "⚔️ 杀死 python.run_rl_swarm 进程 PID: $pid"
    kill -9 "$pid" 2>/dev/null || true
  done
  pgrep -af python | grep Resources | awk '{print $1}' | while read pid; do
    log "⚔️ 杀死 python+Resources 进程 PID: $pid"
    kill -9 "$pid" 2>/dev/null || true
  done
  log "🛑 清理完成"
  if [ "$mode" = "exit" ]; then
    exit 0
  fi
}

# 绑定 Ctrl+C 信号到 cleanup 函数（退出模式）
trap 'cleanup exit' SIGINT

# ====== 🔁 主循环：启动和监控 RL Swarm ======
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  log "🚀 第 $((RETRY_COUNT + 1)) 次尝试：启动 RL Swarm..."

  # ✅ 设置 MPS 环境（适用于 Mac M1/M2）
  export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
  export PYTORCH_ENABLE_MPS_FALLBACK=1
  source ~/.zshrc 2>/dev/null || true

  # ✅ 检查并杀死残留的 p2pd 进程
  if pgrep -x "p2pd" >/dev/null; then
    log "🔍 发现残留的 p2pd 进程，正在终止..."
    pkill -9 p2pd
    log "✅ p2pd 进程已终止"
  fi

  # ✅ 在后台启动主脚本并自动输入空值
  WANDB_MODE=disabled ./run_rl_swarm.sh &
  RL_PID=$!

  # ✅ 循环检测 Python 子进程初始化
  sleep 300
  PY_PID=$(pgrep -P $RL_PID -f python | head -n 1)

  if [ -z "$PY_PID" ]; then
    log "⚠️ No Python subprocess found. Likely failed to start."
  else
    log "✅ Python subprocess detected. PID: $PY_PID"
  fi

  # ✅ 监控子进程
  DISK_LIMIT_GB=10 # 你设定的磁盘阈值（单位：GB）
  MEM_CHECK_INTERVAL=600  # 检查间隔（秒），10分钟

  MEM_CHECK_TIMER=0

  while [ -n "$PY_PID" ] && kill -0 "$PY_PID" >/dev/null 2>&1; do
    sleep 2
    MEM_CHECK_TIMER=$((MEM_CHECK_TIMER + 2))
    if [ $MEM_CHECK_TIMER -ge $MEM_CHECK_INTERVAL ]; then
      MEM_CHECK_TIMER=0
      # 只检测根分区磁盘剩余空间，适配 macOS 和 Ubuntu
      if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        FREE_GB=$(df -g / | awk 'NR==2 {print $4}')
      else
        # Linux/Ubuntu
        FREE_GB=$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
      fi
      log "🔍 检测到磁盘剩余空间 ${FREE_GB}GB"
      if [ "$FREE_GB" -lt "$DISK_LIMIT_GB" ]; then
        log "🚨 磁盘空间不足（${FREE_GB}GB < ${DISK_LIMIT_GB}GB），自动重启！"
        cleanup restart
        break
      fi
    fi
  done

  # ✅ 清理并准备重启
  cleanup restart

  RETRY_COUNT=$((RETRY_COUNT + 1))

  if [ $RETRY_COUNT -eq $WARNING_THRESHOLD ]; then
    log "🚨 警告：RL Swarm 已重启 $WARNING_THRESHOLD 次，请检查系统状态"
  fi

  sleep 2
done

# ❌ 达到最大重试次数
log "🛑 已达到最大重试次数 ($MAX_RETRIES)，程序退出"
