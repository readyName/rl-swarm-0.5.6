#!/bin/bash

CONFIG_FILE="rgym_exp/config/rg-swarm.yaml"

read -p "请输入新的 initial_peers IP: " NEW_IP

if [[ -z "$NEW_IP" ]]; then
  echo "❌ IP 不能为空，脚本退出。"
  exit 1
fi

# 备份原文件
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

# 替换 initial_peers 下的 IP
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  sed -i '' "s/\/ip4\/38\.101\.215\.12\//\/ip4\/${NEW_IP}\//g" "$CONFIG_FILE"
  sed -i '' "s/\/ip4\/38\.101\.215\.13\//\/ip4\/${NEW_IP}\//g" "$CONFIG_FILE"
  sed -i '' "s/\/ip4\/38\.101\.215\.14\//\/ip4\/${NEW_IP}\//g" "$CONFIG_FILE"
else
  # Linux
  sed -i "s/\/ip4\/38\.101\.215\.12\//\/ip4\/${NEW_IP}\//g" "$CONFIG_FILE"
  sed -i "s/\/ip4\/38\.101\.215\.13\//\/ip4\/${NEW_IP}\//g" "$CONFIG_FILE"
  sed -i "s/\/ip4\/38\.101\.215\.14\//\/ip4\/${NEW_IP}\//g" "$CONFIG_FILE"
fi

echo "✅ 已将 initial_peers 的 IP 全部替换为：$NEW_IP"
echo "原始文件已备份为：${CONFIG_FILE}.bak"

# 切换到脚本所在目录（假设 go.sh 在项目根目录）
cd "$(dirname "$0")"

# 激活虚拟环境并执行 auto_run.sh
if [ -d ".venv" ]; then
  echo "🔗 正在激活虚拟环境 .venv..."
  source .venv/bin/activate
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