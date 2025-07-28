#!/bin/bash

set -e
set -o pipefail

echo "🚀 Starting one-click RL-Swarm environment deployment..."

# ----------- 检测操作系统 -----------
OS_TYPE="unknown"
if [[ "$(uname -s)" == "Darwin" ]]; then
  OS_TYPE="macos"
elif [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "$ID" == "ubuntu" ]]; then
    OS_TYPE="ubuntu"
  fi
fi

if [[ "$OS_TYPE" == "unknown" ]]; then
  echo "❌ 不支持的操作系统。仅支持 macOS 和 Ubuntu。"
  exit 1
fi

# ----------- /etc/hosts Patch ----------- 
echo "🔧 Checking /etc/hosts configuration..."
if ! grep -q "raw.githubusercontent.com" /etc/hosts; then
  echo "📝 Writing GitHub accelerated Hosts entries..."
  sudo tee -a /etc/hosts > /dev/null <<EOL
199.232.68.133 raw.githubusercontent.com
199.232.68.133 user-images.githubusercontent.com
199.232.68.133 avatars2.githubusercontent.com
199.232.68.133 avatars1.githubusercontent.com
EOL
else
  echo "✅ Hosts are already configured."
fi

# ----------- 安装依赖 -----------
if [[ "$OS_TYPE" == "macos" ]]; then
  echo "🍺 Checking Homebrew..."
  if ! command -v brew &>/dev/null; then
    echo "📥 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "✅ Homebrew 已安装，跳过安装。"
  fi
  # 配置 Brew 环境变量
  BREW_ENV='eval "$(/opt/homebrew/bin/brew shellenv)"'
  if ! grep -q "$BREW_ENV" ~/.zshrc; then
    echo "$BREW_ENV" >> ~/.zshrc
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
  # 安装依赖
  echo "📦 检查并安装 Node.js, Python@3.12, curl, screen, git, yarn..."
  deps=(node python3.12 curl screen git yarn)
  brew_names=(node python@3.12 curl screen git yarn)
  for i in "${!deps[@]}"; do
    dep="${deps[$i]}"
    brew_name="${brew_names[$i]}"
    if ! command -v $dep &>/dev/null; then
      echo "📥 安装 $brew_name..."
      while true; do
        if brew install $brew_name; then
          echo "✅ $brew_name 安装成功。"
          break
        else
          echo "⚠️ $brew_name 安装失败，3秒后重试..."
          sleep 3
        fi
      done
    else
      echo "✅ $dep 已安装，跳过安装。"
    fi
  done
  # Python alias 写入 zshrc
  PYTHON_ALIAS="# Python3.12 Environment Setup"
  if ! grep -q "$PYTHON_ALIAS" ~/.zshrc; then
    cat << 'EOF' >> ~/.zshrc

# Python3.12 Environment Setup
if [[ $- == *i* ]]; then
  alias python="/opt/homebrew/bin/python3.12"
  alias python3="/opt/homebrew/bin/python3.12"
  alias pip="/opt/homebrew/bin/pip3.12"
  alias pip3="/opt/homebrew/bin/pip3.12"
fi
EOF
  fi
  source ~/.zshrc || true
else
  # Ubuntu
  echo "📦 检查并安装 Node.js (最新LTS), Python3, curl, screen, git, yarn..."
  # 检查当前Node.js版本
  if command -v node &>/dev/null; then
    CURRENT_NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//')
    echo "🔍 当前 Node.js 版本: $CURRENT_NODE_VERSION"
    # 获取最新LTS版本
    LATEST_LTS_VERSION=$(curl -s https://nodejs.org/dist/index.json | jq -r '.[0].version' 2>/dev/null | sed 's/v//')
    echo "🔍 最新 LTS 版本: $LATEST_LTS_VERSION"
    
    if [[ "$CURRENT_NODE_VERSION" != "$LATEST_LTS_VERSION" ]]; then
      echo "🔄 检测到版本不匹配，正在更新到最新 LTS 版本..."
      # 卸载旧版本
      sudo apt remove -y nodejs npm || true
      sudo apt autoremove -y || true
      # 清理可能的残留
      sudo rm -rf /usr/local/bin/npm /usr/local/bin/node || true
      sudo rm -rf ~/.npm || true
      # 安装最新LTS版本
      curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
      sudo apt-get install -y nodejs
      echo "✅ Node.js 已更新到最新 LTS 版本"
    else
      echo "✅ Node.js 已是最新 LTS 版本，跳过更新"
    fi
  else
    echo "📥 未检测到 Node.js，正在安装最新 LTS 版本..."
    # 安装最新Node.js（LTS）
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo "✅ Node.js 安装完成"
  fi
  # 其余依赖
  sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl screen git gnupg jq
  # 官方推荐方式，若失败则用npm镜像
  if curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/yarnkey.gpg > /dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list \
    && sudo apt update && sudo apt install -y yarn; then
    echo "✅ yarn 安装成功（官方源）"
    # 升级到最新版yarn（Berry）
    yarn set version stable
    yarn -v
  else
    echo "⚠️ 官方源安装 yarn 失败，尝试用 npm 镜像安装..."
    if ! command -v npm &>/dev/null; then
      sudo apt install -y npm
    fi
    npm config set registry https://registry.npmmirror.com
    npm install -g yarn
    # 升级到最新版yarn（Berry）
    yarn set version stable
    yarn -v
  fi
  # Python alias 写入 bashrc
  PYTHON_ALIAS="# Python3.12 Environment Setup"
  if ! grep -q "$PYTHON_ALIAS" ~/.bashrc; then
    cat << 'EOF' >> ~/.bashrc

# Python3.12 Environment Setup
if [[ $- == *i* ]]; then
  alias python="/usr/bin/python3"
  alias python3="/usr/bin/python3"
  alias pip="/usr/bin/pip3"
  alias pip3="/usr/bin/pip3"
fi
EOF
  fi
  source ~/.bashrc || true
fi

# ----------- 克隆前备份关键文件（优先$HOME/rl-swarm-0.5.3及其user子目录，无则$HOME/rl-swarm-0.5/user） -----------
TMP_USER_FILES="$HOME/rl-swarm-user-files"
mkdir -p "$TMP_USER_FILES"

# swarm.pem
if [ -f "$HOME/rl-swarm-0.5.3/swarm.pem" ]; then
  cp "$HOME/rl-swarm-0.5.3/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "✅ 已备份 rl-swarm-0.5.3/swarm.pem"
elif [ -f "$HOME/rl-swarm-0.5.3/user/keys/swarm.pem" ]; then
  cp "$HOME/rl-swarm-0.5.3/user/keys/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "✅ 已备份 rl-swarm-0.5.3/user/keys/swarm.pem"
elif [ -f "$HOME/rl-swarm-0.5/user/keys/swarm.pem" ]; then
  cp "$HOME/rl-swarm-0.5/user/keys/swarm.pem" "$TMP_USER_FILES/swarm.pem" && echo "✅ 已备份 0.5/user/keys/swarm.pem"
else
  echo "⚠️ 未检测到 swarm.pem，如有需要请手动补齐。"
fi

# userApiKey.json
if [ -f "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userApiKey.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "✅ 已备份 rl-swarm-0.5.3/modal-login/temp-data/userApiKey.json"
elif [ -f "$HOME/rl-swarm-0.5.3/user/modal-login/userApiKey.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/user/modal-login/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "✅ 已备份 rl-swarm-0.5.3/user/modal-login/userApiKey.json"
elif [ -f "$HOME/rl-swarm-0.5/user/modal-login/userApiKey.json" ]; then
  cp "$HOME/rl-swarm-0.5/user/modal-login/userApiKey.json" "$TMP_USER_FILES/userApiKey.json" && echo "✅ 已备份 0.5/user/modal-login/userApiKey.json"
else
  echo "⚠️ 未检测到 userApiKey.json，如有需要请手动补齐。"
fi

# userData.json
if [ -f "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userData.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/modal-login/temp-data/userData.json" "$TMP_USER_FILES/userData.json" && echo "✅ 已备份 rl-swarm-0.5.3/modal-login/temp-data/userData.json"
elif [ -f "$HOME/rl-swarm-0.5.3/user/modal-login/userData.json" ]; then
  cp "$HOME/rl-swarm-0.5.3/user/modal-login/userData.json" "$TMP_USER_FILES/userData.json" && echo "✅ 已备份 rl-swarm-0.5.3/user/modal-login/userData.json"
elif [ -f "$HOME/rl-swarm-0.5/user/modal-login/userData.json" ]; then
  cp "$HOME/rl-swarm-0.5/user/modal-login/userData.json" "$TMP_USER_FILES/userData.json" && echo "✅ 已备份 0.5/user/modal-login/userData.json"
else
  echo "⚠️ 未检测到 userData.json，如有需要请手动补齐。"
fi

# ----------- Clone Repo ----------- 
if [[ -d "rl-swarm" ]]; then
  echo "⚠️ 检测到已存在目录 'rl-swarm'。"
  read -p "是否覆盖（删除后重新克隆）该目录？(y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "🗑️ 正在删除旧目录..."
    rm -rf rl-swarm
    echo "📥 正在克隆 rl-swarm 仓库..."
    git clone https://github.com/readyName/rl-swarm.git
  else
    echo "❌ 跳过克隆，继续后续流程。"
  fi
else
  echo "📥 正在克隆 rl-swarm 仓库..."
  git clone https://github.com/readyName/rl-swarm.git
fi

# ----------- 复制临时目录中的 user 关键文件 -----------
KEY_DST="rl-swarm/swarm.pem"
MODAL_DST="rl-swarm/modal-login/temp-data"
mkdir -p "$MODAL_DST"

if [ -f "$TMP_USER_FILES/swarm.pem" ]; then
  cp "$TMP_USER_FILES/swarm.pem" "$KEY_DST" && echo "✅ 恢复 swarm.pem 到新目录" || echo "⚠️ 恢复 swarm.pem 失败"
else
  echo "⚠️ 临时目录缺少 swarm.pem，如有需要请手动补齐。"
fi

for fname in userApiKey.json userData.json; do
  if [ -f "$TMP_USER_FILES/$fname" ]; then
    cp "$TMP_USER_FILES/$fname" "$MODAL_DST/$fname" && echo "✅ 恢复 $fname 到新目录" || echo "⚠️ 恢复 $fname 失败"
  else
    echo "⚠️ 临时目录缺少 $fname，如有需要请手动补齐。"
  fi
  
done

# ----------- 生成桌面可双击运行的 .command 文件 -----------
if [[ "$OS_TYPE" == "macos" ]]; then
  PROJECT_DIR="$HOME/rl-swarm"
  DESKTOP_DIR="$HOME/Desktop"
  mkdir -p "$DESKTOP_DIR"
  for script in gensyn.sh nexus.sh ritual.sh wai.sh startAll.sh; do
    cmd_name="${script%.sh}.command"
    cat > "$DESKTOP_DIR/$cmd_name" <<EOF
#!/bin/bash
cd "$PROJECT_DIR"
./$script
EOF
    chmod +x "$DESKTOP_DIR/$cmd_name"
  done
  echo "✅ 已在桌面生成可双击运行的 .command 文件。"
fi

# ----------- Clean Port 3000 ----------- 
echo "🧹 Cleaning up port 3000..."
pid=$(lsof -ti:3000) && [ -n "$pid" ] && kill -9 $pid && echo "✅ Killed: $pid" || echo "✅ Port 3000 is free."

# ----------- 进入rl-swarm目录并执行----------- 
cd rl-swarm || { echo "❌ 进入 rl-swarm 目录失败"; exit 1; }
chmod +x gensyn.sh

# ----------- IP配置逻辑 -----------
echo "🔧 检查IP配置..."

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
    read -p "请输入新的 initial_peers IP（直接回车跳过IP配置）: " NEW_IP
  fi
else
  read -p "未检测到历史 IP，请输入 initial_peers IP（直接回车跳过IP配置）: " NEW_IP
fi

# 每次都将环境变量中的IP写入 ~/.zshrc，保证同步
if [ -n "$CURRENT_IP" ]; then
  sed -i '' "/^export $ENV_VAR=/d" "$ZSHRC"
  echo "export $ENV_VAR=$CURRENT_IP" >> "$ZSHRC"
  echo "✅ 已同步环境变量IP到配置文件：$CURRENT_IP"
fi

# 继续后续逻辑
if [[ -z "$NEW_IP" ]]; then
  echo "ℹ️ 未输入IP，跳过所有IP相关配置，继续执行。"
else
  # 只要有NEW_IP都写入一次配置文件
  sed -i '' "/^export $ENV_VAR=/d" "$ZSHRC"
  echo "export $ENV_VAR=$NEW_IP" >> "$ZSHRC"
  echo "✅ 已写入IP到配置文件：$NEW_IP"
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
    # 无论路由是否存在，都强制添加/覆盖
    if [[ "$OSTYPE" == "darwin"* ]]; then
      # macOS
      sudo route -n add -host $NEW_IP $GATEWAY 2>/dev/null || sudo route change -host $NEW_IP $GATEWAY 2>/dev/null
      echo "🌐 已为 $NEW_IP 强制添加直连路由（不走 VPN），网关：$GATEWAY"
    else
      # Linux
      sudo route add -host $NEW_IP $GATEWAY 2>/dev/null || sudo route change -host $NEW_IP $GATEWAY 2>/dev/null
      echo "🌐 已为 $NEW_IP 强制添加直连路由（不走 VPN），网关：$GATEWAY"
    fi
  fi
fi

# ----------- 执行gensyn.sh -----------
echo "🚀 执行 ./gensyn.sh ..."
./gensyn.sh 