 #!/bin/bash

# -------- 颜色设置 --------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# -------- 操作系统检测 --------
OS=$(uname -s)
case "$OS" in
  Darwin) OS_TYPE="macOS" ;;
  Linux)
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      [[ "$ID" == "ubuntu" ]] && OS_TYPE="Ubuntu" || OS_TYPE="Linux"
    else
      OS_TYPE="Linux"
    fi
    ;;
  *) echo -e "${RED}不支持的系统: $OS${NC}"; exit 1 ;;
esac

# -------- Shell 配置 --------
if [[ -n "$ZSH_VERSION" ]]; then
  SHELL_TYPE="zsh"
  CONFIG_FILE="$HOME/.zshrc"
elif [[ -n "$BASH_VERSION" ]]; then
  SHELL_TYPE="bash"
  CONFIG_FILE="$HOME/.bashrc"
else
  echo -e "${RED}不支持的 shell 类型。${NC}"
  exit 1
fi

# -------- 通用函数 --------
print_header() {
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}=====================================${NC}"
}

check_command() {
  command -v "$1" &>/dev/null
}

configure_shell() {
  local path_to_add="$1"
  local export_cmd="export PATH=$path_to_add:\$PATH"

  if ! grep -q "$path_to_add" "$CONFIG_FILE"; then
    echo "$export_cmd" >>"$CONFIG_FILE"
    echo -e "${GREEN}添加路径到 $CONFIG_FILE：$path_to_add${NC}"
  fi

  source "$CONFIG_FILE" &>/dev/null || echo -e "${YELLOW}请手动执行: source $CONFIG_FILE${NC}"
}

install_nexus_cli() {
  local retries=3
  for i in $(seq 1 $retries); do
    echo -e "${BLUE}尝试安装 Nexus CLI (第 $i 次)...${NC}"
    curl -sSf https://cli.nexus.xyz/ | sh && break
    echo -e "${RED}安装失败，重试中...${NC}"
    sleep 2
  done

  configure_shell "$HOME/.nexus/bin"
  export PATH="$HOME/.nexus/bin:$PATH"

  if check_command nexus; then
    echo -e "${GREEN}Nexus CLI 安装成功。版本信息：${NC}"
    nexus-network --version || echo -e "${YELLOW}无法获取版本信息。${NC}"
  else
    echo -e "${RED}Nexus CLI 安装失败，继续执行后续操作...${NC}"
  fi
}

log_with_timestamp() {
  while IFS= read -r line; do
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $line"
  done
}

start_node_with_logging() {
  local node_id="$1"
  local log_file="$HOME/nexus.log"

  echo -e "${BLUE}启动 Nexus 节点，Node ID: ${node_id}${NC}"
  echo -e "${GREEN}日志输出到: ${log_file}${NC}"

  screen -S nexus_node -X quit &>/dev/null
  screen -dmS nexus_node bash -c "nexus-network start --node-id '$node_id' 2>&1 | tee -a '$log_file'"

  sleep 2
  if screen -list | grep -q "nexus_node"; then
    echo -e "${GREEN}Nexus 节点已在 screen 中运行 (nexus_node)${NC}"
    tail -f "$log_file" | log_with_timestamp
  else
    echo -e "${RED}启动失败，请检查日志。${NC}"
    cat "$log_file"
    exit 1
  fi
}

load_node_id() {
  local config="$HOME/.nexus/config.json"
  local node_id=""

  if [[ -f "$config" ]]; then
    node_id=$(jq -r .node_id "$config" 2>/dev/null)
    echo -e "${BLUE}当前 Node ID: ${GREEN}${node_id}${NC}"
    read -rp "是否使用此 Node ID? (Y/n): " choice
    [[ "$choice" =~ ^[Nn]$ ]] && node_id=""
  fi

  if [[ -z "$node_id" ]]; then
    read -rp "请输入新的 Node ID: " node_id
    mkdir -p "$HOME/.nexus"
    echo "{\"node_id\": \"${node_id}\"}" >"$config"
    echo -e "${GREEN}配置已写入：$config${NC}"
  fi

  echo "$node_id"
}

# -------- 主菜单 --------
main_menu() {
  clear
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE} Nexus 节点部署工具 ($OS_TYPE, $SHELL_TYPE)${NC}"
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${GREEN}请选择一个选项：${NC}"
  echo "1) 手动更新 Nexus CLI 并写入环境变量"
  echo "2) 自动更新 Nexus CLI 并运行节点"
  echo "3) 退出"
  echo -n "请输入选项 [1-3]: "
  read -r choice

  case "$choice" in
    1)
      print_header "手动更新 Nexus CLI"
      install_nexus_cli
      ;;
    2)
      print_header "自动更新并运行节点"
      install_nexus_cli
      NODE_ID=$(load_node_id)
      start_node_with_logging "$NODE_ID"
      ;;
    3)
      echo -e "${BLUE}再见！${NC}"
      exit 0
      ;;
    *)
      echo -e "${RED}无效输入，请重试。${NC}"
      sleep 2
      main_menu
      ;;
  esac
}

main_menu
