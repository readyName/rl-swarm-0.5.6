#!/bin/bash

export WANDB_MODE=disabled  # 完全禁用 W&B

MAX_RETRIES=1000000
WARNING_THRESHOLD=10
RETRY_COUNT=0

# ====== 📝 带时间戳的日志函数 ======
log() {
  echo "【📅 $(date '+%Y-%m-%d %H:%M:%S')】 $1"
}

# ====== 🛑 处理 Ctrl+C 退出信号 ======
cleanup() {
  log "🛑 检测到 Ctrl+C，正在清理进程..."
  # 杀死主进程
  if [ -n "$RL_PID" ] && kill -0 "$RL_PID" 2>/dev/null; then
    log "🧨 杀死主进程 PID: $RL_PID"
    kill -9 "$RL_PID" 2>/dev/null
  fi
  # 清理特定的 Python 子进程
  if [ -n "$PY_PID" ] && kill -0 "$PY_PID" 2>/dev/null; then
    log "⚔️ 杀死 Python 子进程 PID: $PY_PID"
    kill -9 "$PY_PID" 2>/dev/null
  else
    log "⚠️ 未找到 Python 子进程 PID: $PY_PID"
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
  log "🛑 清理完成，程序退出"
  exit 0
}

# 绑定 Ctrl+C 信号到 cleanup 函数
trap cleanup SIGINT

# ====== 🔁 主循环：启动和监控 RL Swarm ======
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  log "🚀 第 $((RETRY_COUNT + 1)) 次尝试：启动 RL Swarm..."

  # ✅ 设置 MPS 环境（适用于 Mac M1/M2）
  #export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
  #export PYTORCH_ENABLE_MPS_FALLBACK=1
  source ~/.zshrc

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
  sleep 600
  PY_PID=$(pgrep -P $RL_PID -f python | head -n 1)

  if [ -z "$PY_PID" ]; then
    log "⚠️ No Python subprocess found. Likely failed to start."
  else
    log "✅ Python subprocess detected. PID: $PY_PID"
  fi

  # ✅ 监控子进程
  while [ -n "$PY_PID" ] && kill -0 "$PY_PID" >/dev/null 2>&1; do
    sleep 2
  done

  # ✅ 清理并准备重启
  log "⚠️ Python 子进程已退出，准备重启..."
  # 检查并释放端口 3000
  log "🌐 检查端口 3000 状态..."
  PORT_PID=$(lsof -ti:3000)
  if [ -n "$PORT_PID" ]; then
    log "⚠️ 端口 3000 被 PID $PORT_PID 占用，正在释放..."
    kill -9 "$PORT_PID" 2>/dev/null
    log "✅ 端口 3000 已释放"
  else
    log "✅ 端口 3000 已空闲"
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))

  if [ $RETRY_COUNT -eq $WARNING_THRESHOLD ]; then
    log "🚨 警告：RL Swarm 已重启 $WARNING_THRESHOLD 次，请检查系统状态"
  fi

  sleep 2
done

# ❌ 达到最大重试次数
log "🛑 已达到最大重试次数 ($MAX_RETRIES)，程序退出"
