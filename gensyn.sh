#!/bin/bash

CONFIG_FILE="rgym_exp/config/rg-swarm.yaml"

ZSHRC=~/.zshrc
ENV_VAR="RL_SWARM_IP"

# 读取 ~/.zshrc 的 RL_SWARM_IP 环境变量
if grep -q "^export $ENV_VAR=" "$ZSHRC"; then
  CURRENT_IP=$(grep "^export $ENV_VAR=" "$ZSHRC" | tail -n1 | awk -F'=' '{print $2}' | tr -d '[:space:]')
else
  CURRENT_IP=""
fi

# 交互提示（10秒超时）
if [ -n "$CURRENT_IP" ]; then
  echo -n "检测到上次使用的 IP: $CURRENT_IP，是否继续使用？(Y/n, 10秒后默认Y): "
  read -t 10 USE_LAST
  if [[ "$USE_LAST" == "" || "$USE_LAST" =~ ^[Yy]$ ]]; then
    NEW_IP="$CURRENT_IP"
  else
    read -p "请输入新的 initial_peers IP: " NEW_IP
  fi
else
  read -p "未检测到历史 IP，请输入 initial_peers IP: " NEW_IP
fi

# 新增：如果用户未输入新IP且环境变量也没有历史IP，则跳过IP相关配置，继续执行
if [[ -z "$NEW_IP" ]]; then
  echo "ℹ️ 未输入IP，且环境变量无历史IP，跳过IP相关配置，继续执行。"
else
  # 只有输入了新IP才进行后续IP相关操作
  if [ "$NEW_IP" == "$CURRENT_IP" ]; then
    echo "ℹ️ 未输入新IP，继续使用历史IP，不修改配置文件。"
  else
    # 写入 ~/.zshrc
    if grep -q "^export $ENV_VAR=" "$ZSHRC"; then
      # 替换
      sed -i '' "s/^export $ENV_VAR=.*/export $ENV_VAR=$NEW_IP/" "$ZSHRC"
    else
      # 追加
      echo "export $ENV_VAR=$NEW_IP" >> "$ZSHRC"
    fi

    # 备份原文件
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

    # 替换 initial_peers 下的 IP
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      sed -i '' "s/\/ip4\/[0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}\//\/ip4\/${NEW_IP}\//g" "$CONFIG_FILE"
    else
      # Linux
      sed -i "s/\/ip4\/[0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}\//\/ip4\/${NEW_IP}\//g" "$CONFIG_FILE"
    fi

    echo "✅ 已将 initial_peers 的 IP 全部替换为：$NEW_IP"
    echo "原始文件已备份为：${CONFIG_FILE}.bak"

    # 添加路由让该 IP 直连本地网关（不走 VPN）
    if [[ "$OSTYPE" == "darwin"* || "$OSTYPE" == "linux"* ]]; then
      GATEWAY=$(netstat -nr | grep '^default' | awk '{print $2}' | head -n1)
      # 检查路由是否已存在
      if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if netstat -nr | grep -q "$NEW_IP"; then
          echo "🌐 路由已存在，跳过添加：$NEW_IP"
        else
          sudo route -n add $NEW_IP $GATEWAY 2>/dev/null || sudo route add -host $NEW_IP $GATEWAY 2>/dev/null
          echo "🌐 已为 $NEW_IP 添加直连路由（不走 VPN）"
        fi
      else
        # Linux
        if ip route show | grep -q "$NEW_IP"; then
          echo "🌐 路由已存在，跳过添加：$NEW_IP"
        else
          sudo route add -host $NEW_IP $GATEWAY 2>/dev/null
          echo "🌐 已为 $NEW_IP 添加直连路由（不走 VPN）"
        fi
      fi
    fi
  fi
fi

# 切换到脚本所在目录（假设 go.sh 在项目根目录）
cd "$(dirname "$0")"

# 激活虚拟环境并执行 auto_run.sh
if [ -d ".venv" ]; then
  echo "🔗 正在激活虚拟环境 .venv..."
  source .venv/bin/activate
  # 检查并安装web3
  if ! python -c "import web3" 2>/dev/null; then
    echo "⚙️ 正在为虚拟环境安装 web3..."
    pip install web3
  fi
else
  echo "⚠️ 未找到 .venv 虚拟环境，正在自动创建..."
  if command -v python3.12 >/dev/null 2>&1; then
    PYTHON=python3.12
  elif command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
  else
    echo "❌ 未找到 Python 3.12 或 python3，请先安装。"
    exit 1
  fi
  $PYTHON -m venv .venv
  if [ -d ".venv" ]; then
    echo "✅ 虚拟环境创建成功，正在激活..."
    source .venv/bin/activate
    # 检查并安装web3
    if ! python -c "import web3" 2>/dev/null; then
      echo "⚙️ 正在为虚拟环境安装 web3..."
      pip install web3
    fi
  else
    echo "❌ 虚拟环境创建失败，跳过激活。"
  fi
fi

# 执行 auto_run.sh
if [ -f "./auto_run.sh" ]; then
  echo "🚀 执行 ./auto_run.sh ..."
  ./auto_run.sh
else
  echo "❌ 未找到 auto_run.sh，无法执行。"
fi