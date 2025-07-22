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

# ====== Peer ID 查询并写入桌面函数 ======
query_and_save_peerid_info() {
  local peer_id="$1"
  local desktop_path=~/Desktop/peerid_info.txt
  local output
  output=$(.venv/bin/python ./gensyncheck.py "$peer_id" | tee -a "$desktop_path")
  if echo "$output" | grep -q "__NEED_RESTART__"; then
    log "⚠️ 超过4小时未有新交易，自动重启！"
    cleanup restart
  fi
  log "✅ 已尝试查询 Peer ID 合约参数，结果已追加写入桌面: $desktop_path"
}

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
    log "⚠️ 未找到 Python 子进程，将监控 RL_PID: $RL_PID 替代 PY_PID"
  else
    log "✅ 检测到 Python 子进程，PID: $PY_PID"
  fi

  # ====== 检测并保存 Peer ID ======
  PEERID_LOG="logs/swarm_launcher.log"
  PEERID_FILE="peerid.txt"
  # 启动时不再主动检测和保存 PeerID，延后到定时任务中

  # ✅ 监控进程（根据 PY_PID 是否存在选择 RL_PID 或 PY_PID）
  DISK_LIMIT_GB=20
  MEM_CHECK_INTERVAL=600
  MEM_CHECK_TIMER=0
  PEERID_QUERY_INTERVAL=10800
  PEERID_QUERY_TIMER=0
  FIRST_QUERY_DONE=0

  # 如果未找到 PY_PID，使用 RL_PID 进行监控
  if [ -z "$PY_PID" ]; then
    MONITOR_PID=$RL_PID
    log "🔍 开始监控 RL_PID: $MONITOR_PID"
  else
    MONITOR_PID=$PY_PID
    log "🔍 开始监控 PY_PID: $MONITOR_PID"
  fi

  while kill -0 "$MONITOR_PID" >/dev/null 2>&1; do
    sleep 2
    MEM_CHECK_TIMER=$((MEM_CHECK_TIMER + 2))
    PEERID_QUERY_TIMER=$((PEERID_QUERY_TIMER + 2))
    if [ $MEM_CHECK_TIMER -ge $MEM_CHECK_INTERVAL ]; then
      MEM_CHECK_TIMER=0
      if [[ "$OSTYPE" == "darwin"* ]]; then
        FREE_GB=$(df -g / | awk 'NR==2 {print $4}')
      else
        FREE_GB=$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')
      fi
      log "🔍 检测到磁盘剩余空间 ${FREE_GB}GB"
      if [ "$FREE_GB" -lt "$DISK_LIMIT_GB" ]; then
        log "🚨 磁盘空间不足（${FREE_GB}GB < ${DISK_LIMIT_GB}GB），自动重启！"
        cleanup restart
        break
      fi
    fi

    if [ $PEERID_QUERY_TIMER -ge $PEERID_QUERY_INTERVAL ]; then
      if [ -f "$PEERID_LOG" ]; then
        PEER_ID=$(grep "Peer ID" "$PEERID_LOG" | sed -n 's/.*Peer ID \[\(.*\)\].*/\1/p' | tail -n1)
        if [ -n "$PEER_ID" ]; then
          echo "$PEER_ID" > "$PEERID_FILE"
          log "✅ 已检测并保存 Peer ID: $PEER_ID"
        else
          log "⏳ 未检测到 Peer ID，本轮跳过参数和链上查询..."
          continue
        fi
      else
        log "⏳ 未检测到 Peer ID 日志文件，本轮跳过参数和链上查询..."
        continue
      fi
      query_and_save_peerid_info "$PEER_ID"
      FIRST_QUERY_DONE=1
      PEERID_QUERY_TIMER=0
    fi
  done

  # ✅ 清理并准备重启
  log "🚨 监控进程 PID: $MONITOR_PID 已终止，进入重启流程"
  cleanup restart
  RETRY_COUNT=$((RETRY_COUNT + 1))

  if [ $RETRY_COUNT -eq $WARNING_THRESHOLD ]; then
    log "🚨 警告：RL Swarm 已重启 $WARNING_THRESHOLD 次，请检查系统状态"
  fi

  sleep 2
done

log "🛑 已达到最大重试次数 ($MAX_RETRIES)，程序退出"