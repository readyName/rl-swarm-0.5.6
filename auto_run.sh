#!/bin/bash

export WANDB_MODE=disabled  # 完全禁用 W&B

MAX_RETRIES=1000000
WARNING_THRESHOLD=10
RETRY_COUNT=0

# ====== ✅ Log with timestamp ======
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ====== 🔁 Start daemon loop ======
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  log "🚀 Attempt $((RETRY_COUNT + 1)): Starting RL Swarm..."

  # ✅ Set MPS environment (for Mac M1/M2 if applicable)
  export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
  export PYTORCH_ENABLE_MPS_FALLBACK=1
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
  sleep 300
  PY_PIDS=$(pgrep -P $RL_PID -f python)

  if [ -z "$PY_PIDS" ]; then
    log "⚠️ No Python subprocess found. Likely failed to start."
  else
    log "✅ Python subprocess detected. PIDs: $PY_PIDS"
  fi

  # ✅ Monitor all subprocesses
  while true; do
    ALL_EXITED=true
    for pid in $PY_PIDS; do
      if kill -0 $pid >/dev/null 2>&1; then
        ALL_EXITED=false
        break
      fi
    done
    if $ALL_EXITED; then
      break
    fi
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