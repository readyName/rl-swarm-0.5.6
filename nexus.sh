#!/bin/bash

# 柔和色彩设置
GREEN='\033[1;32m'      # 柔和绿色
BLUE='\033[1;36m'       # 柔和蓝色
RED='\033[1;31m'        # 柔和红色
YELLOW='\033[1;33m'     # 柔和黄色
NC='\033[0m'            # 无颜色

# 日志文件设置
LOG_FILE="$HOME/nexus.log"
MAX_LOG_SIZE=10485760 # 10MB，日志大小限制

# 检测操作系统
OS=$(uname -s)
case "$OS" in
  Darwin) OS_TYPE="macOS" ;;
  Linux)
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      if [[ "$ID" == "ubuntu" ]]; then
        OS_TYPE="Ubuntu"
      else
        echo -e "${RED}不支持的操作系统: $ID。本脚本仅支持 macOS 和 Ubuntu。${NC}"
        exit 1
      fi
    else
      echo -e "${RED}不支持的操作系统: 未检测到 /etc/os-release。本脚本仅支持 macOS 和 Ubuntu。${NC}"
      exit 1
    fi
    ;;
  *) echo -e "${RED}不支持的操作系统: $OS。本脚本仅支持 macOS 和 Ubuntu。${NC}" ; exit 1 ;;
esac

# 检测 shell 并设置配置文件
if [[ -n "$ZSH_VERSION" ]]; then
  SHELL_TYPE="zsh"
  CONFIG_FILE="$HOME/.zshrc"
elif [[ -n "$BASH_VERSION" ]]; then
  SHELL_TYPE="bash"
  CONFIG_FILE="$HOME/.bashrc"
else
  echo -e "${RED}不支持的 shell。本脚本仅支持 bash 和 zsh。${NC}"
  exit 1
fi

# 打印标题
print_header() {
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}=====================================${NC}"
}

# 检查命令是否存在
check_command() {
  if command -v "$1" &> /dev/null; then
    echo -e "${GREEN}$1 已安装，跳过安装步骤。${NC}"
    return 0
  else
    echo -e "${RED}$1 未安装，开始安装...${NC}"
    return 1
  fi
}

# 配置 shell 环境变量，避免重复写入
configure_shell() {
  local env_path="$1"
  local env_var="export PATH=$env_path:\$PATH"
  if [[ -f "$CONFIG_FILE" ]] && grep -Fx "$env_var" "$CONFIG_FILE" > /dev/null; then
    echo -e "${GREEN}环境变量已在 $CONFIG_FILE 中配置。${NC}"
  else
    echo -e "${BLUE}正在将环境变量添加到 $CONFIG_FILE...${NC}"
    echo "$env_var" >> "$CONFIG_FILE"
    echo -e "${GREEN}环境变量已添加到 $CONFIG_FILE。${NC}"
    # 应用当前会话的更改
    source "$CONFIG_FILE" 2>/dev/null || echo -e "${RED}无法加载 $CONFIG_FILE，请手动运行 'source $CONFIG_FILE'。${NC}"
  fi
}

# 日志轮转
rotate_log() {
  if [[ -f "$LOG_FILE" ]]; then
    if [[ "$OS_TYPE" == "macOS" ]]; then
      FILE_SIZE=$(stat -f %z "$LOG_FILE" 2>/dev/null)
    else
      FILE_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null)
    fi
    if [[ $FILE_SIZE -ge $MAX_LOG_SIZE ]]; then
      mv "$LOG_FILE" "${LOG_FILE}.$(date +%F_%H-%M-%S).bak"
      echo -e "${YELLOW}日志文件已轮转，新日志将写入 $LOG_FILE${NC}"
    fi
  fi
}

# 安装基础依赖（仅 Ubuntu）
install_dependencies() {
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    print_header "安装基础依赖工具"
    echo -e "${BLUE}更新 apt 包索引并安装必要工具...${NC}"
    sudo apt-get update -y
    sudo apt-get install -y curl jq screen build-essential || {
      echo -e "${RED}安装依赖工具失败，请检查网络连接或权限。${NC}"
      exit 1
    }
  fi
}

# 安装 Homebrew（仅 macOS）
install_homebrew() {
  if [[ "$OS_TYPE" == "macOS" ]]; then
    print_header "检查 Homebrew 安装"
    if check_command brew; then
      return
    fi
    echo -e "${BLUE}在 $OS_TYPE 上安装 Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      echo -e "${RED}安装 Homebrew 失败，请检查网络连接或权限。${NC}"
      exit 1
    }
    configure_shell "/opt/homebrew/bin"
  fi
}

# 安装 CMake
install_cmake() {
  print_header "检查 CMake 安装"
  if check_command cmake; then
    return
  fi
  echo -e "${BLUE}正在安装 CMake...${NC}"
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    sudo apt-get install -y cmake || {
      echo -e "${RED}安装 CMake 失败，请检查网络连接或权限。${NC}"
      exit 1
    }
  else
    brew install cmake || {
      echo -e "${RED}安装 CMake 失败，请检查 Homebrew 安装。${NC}"
      exit 1
    }
  fi
}

# 安装 Protobuf
install_protobuf() {
  print_header "检查 Protobuf 安装"
  if check_command protoc; then
    return
  fi
  echo -e "${BLUE}正在安装 Protobuf...${NC}"
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    sudo apt-get install -y protobuf-compiler || {
      echo -e "${RED}安装 Protobuf 失败，请检查网络连接或权限。${NC}"
      exit 1
    }
  else
    brew install protobuf || {
      echo -e "${RED}安装 Protobuf 失败，请检查 Homebrew 安装。${NC}"
      exit 1
    }
  fi
}

# 安装 Rust
install_rust() {
  print_header "检查 Rust 安装"
  if check_command rustc; then
    return
  fi
  echo -e "${BLUE}正在安装 Rust...${NC}"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || {
    echo -e "${RED}安装 Rust 失败，请检查网络连接。${NC}"
    exit 1
  }
  source "$HOME/.cargo/env" 2>/dev/null || echo -e "${RED}无法加载 Rust 环境，请手动运行 'source ~/.cargo/env'。${NC}"
  configure_shell "$HOME/.cargo/bin"
}

# 配置 Rust RISC-V 目标
configure_rust_target() {
  print_header "检查 Rust RISC-V 目标"
  if rustup target list --installed | grep -q "riscv32i-unknown-none-elf"; then
    echo -e "${GREEN}RISC-V 目标 (riscv32i-unknown-none-elf) 已安装，跳过。${NC}"
    return
  fi
  echo -e "${BLUE}为 Rust 添加 RISC-V 目标...${NC}"
  rustup target add riscv32i-unknown-none-elf || {
    echo -e "${RED}添加 RISC-V 目标失败，请检查 Rust 安装。${NC}"
    exit 1
  }
}

# 日志函数
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" | tee -a "$LOG_FILE"
  rotate_log
}

# 退出时的清理函数
cleanup_exit() {
  log "${YELLOW}收到退出信号，正在清理 Nexus 节点进程和 screen 会话...${NC}"
  if screen -list | grep -q "nexus_node"; then
    log "${BLUE}正在终止 nexus_node screen 会话...${NC}"
    screen -S nexus_node -X quit 2>/dev/null || log "${RED}无法终止 screen 会话，请检查权限或会话状态。${NC}"
  else
    log "${GREEN}未找到 nexus_node screen 会话，无需清理。${NC}"
  fi
  # 查找 nexus-network 和 nexus-cli 进程
  PIDS=$(pgrep -f "nexus-network start --node-id\|nexus-cli start --node-id" | tr '\n' ' ' | xargs echo -n)
  if [[ -n "$PIDS" ]]; then
    for pid in $PIDS; do
      if ps -p "$pid" > /dev/null 2>&1; then
        log "${BLUE}正在终止 Nexus 节点进程 (PID: $pid)...${NC}"
        kill -9 "$pid" 2>/dev/null || log "${RED}无法终止 PID $pid 的进程，请检查进程状态。${NC}"
      fi
    done
  else
    log "${GREEN}未找到 nexus-network 或 nexus-cli 进程。${NC}"
  fi
  log "${GREEN}清理完成，脚本退出。${NC}"
  exit 0
}

# 重启时的清理函数
cleanup_restart() {
  log "${YELLOW}准备重启节点，先进行清理...${NC}"
  if screen -list | grep -q "nexus_node"; then
    log "${BLUE}正在终止 nexus_node screen 会话...${NC}"
    screen -S nexus_node -X quit 2>/dev/null || log "${RED}无法终止 screen 会话，请检查权限或会话状态。${NC}"
  else
    log "${GREEN}未找到 nexus_node screen 会话，无需清理。${NC}"
  fi
  # 查找 nexus-network 和 nexus-cli 进程
  PIDS=$(pgrep -f "nexus-network start --node-id\|nexus-cli start --node-id" | tr '\n' ' ' | xargs echo -n)
  if [[ -n "$PIDS" ]]; then
    for pid in $PIDS; do
      if ps -p "$pid" > /dev/null 2>&1; then
        log "${BLUE}正在终止 Nexus 节点进程 (PID: $pid)...${NC}"
        kill -9 "$pid" 2>/dev/null || log "${RED}无法终止 PID $pid 的进程，请检查进程状态。${NC}"
      fi
    done
  else
    log "${GREEN}未找到 nexus-network 或 nexus-cli 进程。${NC}"
  fi
  log "${GREEN}清理完成，准备重启节点。${NC}"
}

trap 'cleanup_exit' SIGINT SIGTERM SIGHUP

# 安装或更新 Nexus CLI
install_nexus_cli() {
  local attempt=1
  local max_attempts=3
  local success=false
  while [[ $attempt -le $max_attempts ]]; do
    log "${BLUE}正在安装/更新 Nexus CLI（第 $attempt/$max_attempts 次）...${NC}"
    if curl -s https://cli.nexus.xyz/ | sh &>/dev/null; then
      log "${GREEN}Nexus CLI 安装/更新成功！${NC}"
      success=true
      break
    else
      log "${YELLOW}第 $attempt 次安装/更新 Nexus CLI 失败。${NC}"
      ((attempt++))
      sleep 2
    fi
  done
  # 确保配置文件存在，如果没有就生成并写入 PATH 变量
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "export PATH=\"$HOME/.cargo/bin:\$PATH\"" > "$CONFIG_FILE"
    log "${YELLOW}未检测到 $CONFIG_FILE，已自动生成并写入 PATH 变量。${NC}"
  fi
  source "$CONFIG_FILE" 2>/dev/null && log "${GREEN}已自动加载 $CONFIG_FILE 环境变量。${NC}" || log "${YELLOW}未能自动加载 $CONFIG_FILE，请手动执行 source $CONFIG_FILE。${NC}"
  if [[ "$success" == false ]]; then
    log "${RED}Nexus CLI 安装/更新失败 $max_attempts 次，将尝试使用当前版本运行节点。${NC}"
  fi
  if command -v nexus-network &>/dev/null; then
    log "${GREEN}nexus-network 版本：$(nexus-network --version 2>/dev/null)${NC}"
  elif command -v nexus-cli &>/dev/null; then
    log "${GREEN}nexus-cli 版本：$(nexus-cli --version 2>/dev/null)${NC}"
  else
    log "${RED}未找到 nexus-network 或 nexus-cli，无法运行节点。${NC}"
    exit 1
  fi
}

# 读取或设置 Node ID，添加 5 秒超时
get_node_id() {
  CONFIG_PATH="$HOME/.nexus/config.json"
  if [[ -f "$CONFIG_PATH" ]]; then
    CURRENT_NODE_ID=$(jq -r .node_id "$CONFIG_PATH" 2>/dev/null)
    if [[ -n "$CURRENT_NODE_ID" && "$CURRENT_NODE_ID" != "null" ]]; then
      log "${GREEN}检测到配置文件中的 Node ID：$CURRENT_NODE_ID${NC}"
      echo -e "${BLUE}是否使用此 Node ID? (y/n, 默认 y，5 秒后自动继续): ${NC}"
      use_old_id=""
      read -t 5 -r use_old_id
      use_old_id=${use_old_id:-y} # 默认 y
      if [[ "$use_old_id" =~ ^[Nn]$ ]]; then
        read -rp "请输入新的 Node ID: " NODE_ID_TO_USE
        # 验证 Node ID（假设需要非空且只包含字母、数字、连字符）
        if [[ -z "$NODE_ID_TO_USE" || ! "$NODE_ID_TO_USE" =~ ^[a-zA-Z0-9-]+$ ]]; then
          log "${RED}无效的 Node ID，请输入只包含字母、数字或连字符的 ID。${NC}"
          exit 1
        fi
        jq --arg id "$NODE_ID_TO_USE" '.node_id = $id' "$CONFIG_PATH" > "$CONFIG_PATH.tmp" && mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"
        log "${GREEN}已更新 Node ID: $NODE_ID_TO_USE${NC}"
      else
        NODE_ID_TO_USE="$CURRENT_NODE_ID"
      fi
    else
      log "${YELLOW}未检测到有效 Node ID，请输入新的 Node ID。${NC}"
      read -rp "请输入新的 Node ID: " NODE_ID_TO_USE
      if [[ -z "$NODE_ID_TO_USE" || ! "$NODE_ID_TO_USE" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log "${RED}无效的 Node ID，请输入只包含字母、数字或连字符的 ID。${NC}"
        exit 1
      fi
      mkdir -p "$HOME/.nexus"
      echo "{\"node_id\": \"${NODE_ID_TO_USE}\"}" > "$CONFIG_PATH"
      log "${GREEN}已写入 Node ID: $NODE_ID_TO_USE 到 $CONFIG_PATH${NC}"
    fi
  else
    log "${YELLOW}未找到配置文件 $CONFIG_PATH，请输入 Node ID。${NC}"
    read -rp "请输入新的 Node ID: " NODE_ID_TO_USE
    if [[ -z "$NODE_ID_TO_USE" || ! "$NODE_ID_TO_USE" =~ ^[a-zA-Z0-9-]+$ ]]; then
      log "${RED}无效的 Node ID，请输入只包含字母、数字或连字符的 ID。${NC}"
      exit 1
    fi
    mkdir -p "$HOME/.nexus"
    echo "{\"node_id\": \"${NODE_ID_TO_USE}\"}" > "$CONFIG_PATH"
    log "${GREEN}已写入 Node ID: $NODE_ID_TO_USE 到 $CONFIG_PATH${NC}"
  fi
}

# 启动节点
start_node() {
  log "${BLUE}正在启动 Nexus 节点 (Node ID: $NODE_ID_TO_USE)...${NC}"
  rotate_log
  screen -dmS nexus_node bash -c "nexus-network start --node-id '${NODE_ID_TO_USE}' >> $LOG_FILE 2>&1"
  sleep 2
  if screen -list | grep -q "nexus_node"; then
    log "${GREEN}Nexus 节点已在 screen 会话（nexus_node）中启动，日志输出到 $LOG_FILE${NC}"
  else
    log "${YELLOW}nexus-network 启动失败，尝试用 nexus-cli 启动...${NC}"
    screen -dmS nexus_node bash -c "nexus-cli start --node-id '${NODE_ID_TO_USE}' >> $LOG_FILE 2>&1"
    sleep 2
    if screen -list | grep -q "nexus_node"; then
      log "${GREEN}Nexus 节点已通过 nexus-cli 启动，日志输出到 $LOG_FILE${NC}"
    else
      log "${RED}nexus-cli 启动也失败，触发自动重启...${NC}"
      cleanup_restart
      install_nexus_cli
      start_node
      return
    fi
  fi
}

# 主循环
main() {
  install_dependencies
  install_homebrew
  install_cmake
  install_protobuf
  install_rust
  configure_rust_target
  get_node_id
  while true; do
    cleanup_restart
    install_nexus_cli
    # 新增：重启前清理日志
    if [[ -f "$LOG_FILE" ]]; then
      rm -f "$LOG_FILE"
      echo -e "${YELLOW}已清理旧日志文件：$LOG_FILE${NC}"
    fi
    start_node
    log "${BLUE}节点将每隔 4 小时自动重启...${NC}"
    sleep 14400
    cleanup_restart
  done
}

main