#!/bin/bash

# 颜色设置
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

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
                OS_TYPE="Linux"
            fi
        else
            OS_TYPE="Linux"
        fi
        ;;
    *) echo -e "${RED}不支持的操作系统: $OS。本脚本仅支持 macOS、Ubuntu 和其他 Linux 发行版。${NC}" ; exit 1 ;;
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
    if [[ -f "$LOG_FILE" && $(stat -f %z "$LOG_FILE" 2>/dev/null || stat -c %s "$LOG_FILE" 2>/dev/null) -ge $MAX_LOG_SIZE ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.$(date +%F_%H-%M-%S).bak"
        echo -e "${YELLOW}日志文件已轮转，新日志将写入 $LOG_FILE${NC}"
    fi
}
# 安装 Homebrew（macOS 和非 Ubuntu Linux）
install_homebrew() {
    print_header "检查 Homebrew 安装"
    if check_command brew; then
        return
    fi
    echo -e "${BLUE}在 $OS_TYPE 上安装 Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        echo -e "${RED}安装 Homebrew 失败，请检查网络连接或权限。${NC}"
        exit 1
    }
    if [[ "$OS_TYPE" == "macOS" ]]; then
        configure_shell "/opt/homebrew/bin"
    else
        configure_shell "$HOME/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/bin"

        if ! check_command gcc; then
            echo -e "${BLUE}在 Linux 上安装 gcc（Homebrew 依赖）...${NC}"
            if command -v yum &> /dev/null; then
                sudo yum groupinstall 'Development Tools' || {
                    echo -e "${RED}安装 gcc 失败，请手动安装 Development Tools。${NC}"
                    exit 1
                }
            else
                echo -e "${RED}不支持的包管理器，请手动安装 gcc。${NC}"
                exit 1
            fi
        fi
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
        sudo apt-get update && sudo apt-get install -y cmake || {
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
        sudo apt-get update && sudo apt-get install -y protobuf-compiler || {
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
    PIDS=$(pgrep -f "nexus-network start --node-id" | tr '\n' ' ' | xargs echo -n)
    if [[ -n "$PIDS" ]]; then
        for pid in $PIDS; do
            if ps -p "$pid" > /dev/null 2>&1; then
                log "${BLUE}正在终止 Nexus 节点进程 (PID: $pid)...${NC}"
                kill -9 "$pid" 2>/dev/null || log "${RED}无法终止 PID $pid 的进程，请检查进程状态。${NC}"
            fi
        done
    else
        log "${GREEN}未找到 nexus-network 进程。${NC}"
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
    PIDS=$(pgrep -f "nexus-network start --node-id" | tr '\n' ' ' | xargs echo -n)
    if [[ -n "$PIDS" ]]; then
        for pid in $PIDS; do
            if ps -p "$pid" > /dev/null 2>&1; then
                log "${BLUE}正在终止 Nexus 节点进程 (PID: $pid)...${NC}"
                kill -9 "$pid" 2>/dev/null || log "${RED}无法终止 PID $pid 的进程，请检查进程状态。${NC}"
            fi
        done
    else
        log "${GREEN}未找到 nexus-network 进程。${NC}"
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
    if [[ "$success" == false ]]; then
        log "${RED}Nexus CLI 安装/更新失败 $max_attempts 次，将尝试使用当前版本运行节点。${NC}"
    fi
    if command -v nexus-network &>/dev/null; then
        log "${GREEN}当前 Nexus CLI 版本：$(nexus-network --version 2>/dev/null)${NC}"
    else
        log "${RED}未找到 Nexus CLI，无法运行节点。${NC}"
        exit 1
    fi
}

# 读取或设置 Node ID，添加5秒超时
get_node_id() {
    CONFIG_PATH="$HOME/.nexus/config.json"
    if [[ -f "$CONFIG_PATH" ]]; then
        CURRENT_NODE_ID=$(jq -r .node_id "$CONFIG_PATH" 2>/dev/null)
        if [[ -n "$CURRENT_NODE_ID" && "$CURRENT_NODE_ID" != "null" ]]; then
            log "${GREEN}检测到配置文件中的 Node ID：$CURRENT_NODE_ID${NC}"
            # 使用 read -t 5 实现5秒超时，默认选择 y
            echo -e "${BLUE}是否使用此 Node ID? (y/n, 默认 y，5秒后自动继续): ${NC}"
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
        log "${RED}启动 screen 会话失败，请检查日志：$LOG_FILE${NC}"
        cat "$LOG_FILE"
        exit 1
    fi
}

# 主循环
main() {
    get_node_id
    while true; do
        cleanup_restart
        install_nexus_cli
        start_node
        log "${BLUE}节点将每隔4小时自动重启...${NC}"
        sleep 14400
        cleanup_restart
    done
}
main

