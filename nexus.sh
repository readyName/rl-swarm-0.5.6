#!/bin/bash

# 颜色设置
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # 无颜色

# 获取当前时间戳
get_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

# 清理函数：终止 screen 会话和所有 nexus-network 相关进程
cleanup() {
    echo -e "[$(get_timestamp)] ${YELLOW}收到退出信号，正在清理进程和 screen 会话...${NC}"

    # 终止所有 nexus_node 的 screen 会话
    if screen -list | grep -q "nexus_node"; then
        echo -e "[$(get_timestamp)] ${BLUE}正在终止所有 nexus_node screen 会话...${NC}"
        screen -ls | grep "nexus_node" | awk '{print $1}' | while read -r session; do
            echo -e "[$(get_timestamp)] ${BLUE}终止 screen 会话: $session${NC}"
            screen -S "$session" -X quit 2>/dev/null || {
                echo -e "[$(get_timestamp)] ${RED}无法终止 screen 会话 $session，请检查权限或会话状态。${NC}"
            }
        done
    else
        echo -e "[$(get_timestamp)] ${GREEN}未找到 nexus_node screen 会话，无需清理。${NC}"
    fi

    # 终止所有与 nexus-network 相关的进程
    echo -e "[$(get_timestamp)] ${BLUE}正在查找并终止所有 nexus-network 相关进程...${NC}"
    PIDS=$(pgrep -f "nexus-network start --node-id" | tr '\n' ' ' | xargs echo -n)
    if [[ -n "$PIDS" ]]; then
        for pid in $PIDS; do
            if ps -p "$pid" > /dev/null 2>&1; then
                echo -e "[$(get_timestamp)] ${BLUE}正在终止 Nexus 节点进程 (PID: $pid)...${NC}"
                kill -9 "$pid" 2>/dev/null || {
                    echo -e "[$(get_timestamp)] ${RED}无法终止 PID $pid 的进程，请检查进程状态。${NC}"
                }
            else
                echo -e "[$(get_timestamp)] ${YELLOW}PID $pid 已不存在，跳过。${NC}"
            fi
        done
    else
        echo -e "[$(get_timestamp)] ${GREEN}未找到 nexus-network 进程。${NC}"
    fi

    # 终止所有相关的 bash 进程
    echo -e "[$(get_timestamp)] ${BLUE}正在查找并终止所有相关 bash 进程...${NC}"
    BASH_PIDS=$(pgrep -f "bash -c while true.*nexus-network start --node-id" | tr '\n' ' ' | xargs echo -n)
    if [[ -n "$BASH_PIDS" ]]; then
        for pid in $BASH_PIDS; do
            if ps -p "$pid" > /dev/null 2>&1; then
                echo -e "[$(get_timestamp)] ${BLUE}正在终止 bash 进程 (PID: $pid)...${NC}"
                kill -9 "$pid" 2>/dev/null || {
                    echo -e "[$(get_timestamp)] ${RED}无法终止 PID $pid 的 bash 进程，请检查进程状态。${NC}"
                }
            else
                echo -e "[$(get_timestamp)] ${YELLOW}PID $pid 已不存在，跳过。${NC}"
            fi
        done
    else
        echo -e "[$(get_timestamp)] ${GREEN}未找到相关 bash 进程。${NC}"
    fi

    echo -e "[$(get_timestamp)] ${GREEN}清理完成，脚本退出。${NC}"
    exit 0
}

# 设置 Ctrl+C 捕获
trap cleanup SIGINT SIGTERM SIGHUP

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
    *)      echo -e "[$(get_timestamp)] ${RED}不支持的操作系统: $OS。本脚本仅支持 macOS、Ubuntu 和其他 Linux 发行版。${NC}" ; exit 1 ;;
esac

# 检测 shell 并设置配置文件
if [[ -n "$ZSH_VERSION" ]]; then
    SHELL_TYPE="zsh"
    CONFIG_FILE="$HOME/.zshrc"
elif [[ -n "$BASH_VERSION" ]]; then
    SHELL_TYPE="bash"
    CONFIG_FILE="$HOME/.bashrc"
else
    echo -e "[$(get_timestamp)] ${RED}不支持的 shell。本脚本仅支持 bash 和 zsh。${NC}"
    exit 1
fi

# 打印标题
print_header() {
    echo -e "[$(get_timestamp)] ${BLUE}=====================================${NC}"
    echo -e "[$(get_timestamp)] ${BLUE}$1${NC}"
    echo -e "[$(get_timestamp)] ${BLUE}=====================================${NC}"
}

# 检查命令是否存在
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "[$(get_timestamp)] ${GREEN}$1 已安装，跳过安装步骤。${NC}"
        return 0
    else
        echo -e "[$(get_timestamp)] ${RED}$1 未安装，开始安装...${NC}"
        return 1
    fi
}

# 配置 shell 环境变量
configure_shell() {
    local env_path="$1"
    local env_var="export PATH=$env_path:\$PATH"
    if [[ -f "$CONFIG_FILE" ]] && grep -q "$env_path" "$CONFIG_FILE"; then
        echo -e "[$(get_timestamp)] ${GREEN}环境变量已在 $CONFIG_FILE 中配置。${NC}"
    else
        echo -e "[$(get_timestamp)] ${BLUE}正在将环境变量添加到 $CONFIG_FILE...${NC}"
        echo "$env_var" >> "$CONFIG_FILE"
        echo -e "[$(get_timestamp)] ${GREEN}环境变量已添加到 $CONFIG_FILE。${NC}"
        source "$CONFIG_FILE" 2>/dev/null || echo -e "[$(get_timestamp)] ${RED}无法加载 $CONFIG_FILE，请手动运行 'source $CONFIG_FILE'。${NC}"
    fi
}

# 安装 Homebrew（macOS 和非 Ubuntu Linux）
install_homebrew() {
    print_header "检查 Homebrew 安装"
    if check_command brew; then
        return
    fi
    echo -e "[$(get_timestamp)] ${BLUE}在 $OS_TYPE 上安装 Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        echo -e "[$(get_timestamp)] ${RED}安装 Homebrew 失败，请检查网络连接或权限。${NC}"
        exit 1
    }
    if [[ "$OS_TYPE" == "macOS" ]]; then
        configure_shell "/opt/homebrew/bin"
    else
        configure_shell "$HOME/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/bin"
        if ! check_command gcc; then
            echo -e "[$(get_timestamp)] ${BLUE}在 Linux 上安装 gcc（Homebrew 依赖）...${NC}"
            if command -v yum &> /dev/null; then
                sudo yum groupinstall 'Development Tools' || {
                    echo -e "[$(get_timestamp)] ${RED}安装 gcc 失败，请手动安装 Development Tools。${NC}"
                    exit 1
                }
            else
                echo -e "[$(get_timestamp)] ${RED}不支持的包管理器，请手动安装 gcc。${NC}"
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
    echo -e "[$(get_timestamp)] ${BLUE}正在安装 CMake...${NC}"
    if [[ "$OS_TYPE" == "Ubuntu" ]]; then
        sudo apt-get update && sudo apt-get install -y cmake || {
            echo -e "[$(get_timestamp)] ${RED}安装 CMake 失败，请检查网络连接或权限。${NC}"
            exit 1
        }
    else
        brew install cmake || {
            echo -e "[$(get_timestamp)] ${RED}安装 CMake 失败，请检查 Homebrew 安装。${NC}"
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
    echo -e "[$(get_timestamp)] ${BLUE}正在安装 Protobuf...${NC}"
    if [[ "$OS_TYPE" == "Ubuntu" ]]; then
        sudo apt-get update && sudo apt-get install -y protobuf-compiler || {
            echo -e "[$(get_timestamp)] ${RED}安装 Protobuf 失败，请检查网络连接或权限。${NC}"
            exit 1
        }
    else
        brew install protobuf || {
            echo -e "[$(get_timestamp)] ${RED}安装 Protobuf 失败，请检查 Homebrew 安装。${NC}"
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
    echo -e "[$(get_timestamp)] ${BLUE}正在安装 Rust...${NC}"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || {
        echo -e "[$(get_timestamp)] ${RED}安装 Rust 失败，请检查网络连接。${NC}"
        exit 1
    }
    source "$HOME/.cargo/env" 2>/dev/null || echo -e "[$(get_timestamp)] ${RED}无法加载 Rust 环境，请手动运行 'source ~/.cargo/env'。${NC}"
    configure_shell "$HOME/.cargo/bin"
}

# 配置 Rust RISC-V 目标
configure_rust_target() {
    print_header "检查 Rust RISC-V 目标"
    if rustup target list --installed | grep -q "riscv32i-unknown-none-elf"; then
        echo -e "[$(get_timestamp)] ${GREEN}RISC-V 目标 (riscv32i-unknown-none-elf) 已安装，跳过。${NC}"
        return
    fi
    echo -e "[$(get_timestamp)] ${BLUE}为 Rust 添加 RISC-V 目标...${NC}"
    rustup target add riscv32i-unknown-none-elf || {
        echo -e "[$(get_timestamp)] ${RED}添加 RISC-V 目标失败，请检查 Rust 安装。${NC}"
        exit 1
    }
}

# 检查 Nexus CLI 版本
check_nexus_version() {
    print_header "检查 Nexus CLI 版本"
    if command -v nexus-network &> /dev/null; then
        NEXUS_VERSION=$(nexus-network --version 2>/dev/null)
        echo -e "[$(get_timestamp)] ${GREEN}当前 Nexus CLI 版本：${NEXUS_VERSION}${NC}"
    else
        echo -e "[$(get_timestamp)] ${YELLOW}未安装 Nexus CLI，将在启动节点时尝试安装...${NC}"
    fi
}

# 安装或更新 Nexus CLI
install_nexus_cli() {
    print_header "安装或更新 Nexus CLI"
    local attempt=1
    local max_attempts=3
    local success=false

    while [[ $attempt -le $max_attempts ]]; do
        echo -e "[$(get_timestamp)] ${BLUE}尝试安装/更新 Nexus CLI（第 $attempt/$max_attempts 次）...${NC}"
        if curl https://cli.nexus.xyz/ | sh; then
            echo -e "[$(get_timestamp)] ${GREEN}Nexus CLI 安装/更新成功！${NC}"
            success=true
            if [[ -f "$HOME/.zshrc" ]]; then
                source "$HOME/.zshrc"
                echo -e "[$(get_timestamp)] ${GREEN}已自动加载 .zshrc 配置。${NC}"
            elif [[ -f "$HOME/.bashrc" ]]; then
                source "$HOME/.bashrc"
                echo -e "[$(get_timestamp)] ${GREEN}已自动加载 .bashrc 配置。${NC}"
            else
                echo -e "[$(get_timestamp)] ${YELLOW}未找到 shell 配置文件，可能需要手动加载环境变量。${NC}"
            fi
            break
        else
            echo -e "[$(get_timestamp)] ${RED}第 $attempt 次安装/更新 Nexus CLI 失败。${NC}"
            ((attempt++))
            sleep 5
        fi
    done

    if [[ "$success" == false ]]; then
        echo -e "[$(get_timestamp)] ${YELLOW}Nexus CLI 安装/更新失败 $max_attempts 次，将尝试使用当前版本运行节点。${NC}"
    fi

    if command -v nexus-network &> /dev/null; then
        NEXUS_VERSION=$(nexus-network --version 2>/dev/null)
        echo -e "[$(get_timestamp)] ${GREEN}当前 Nexus CLI 版本：${NEXUS_VERSION}${NC}"
    else
        echo -e "[$(get_timestamp)] ${RED}未找到 Nexus CLI，无法运行节点。${NC}"
        exit 1
    fi
}

# 运行节点
run_node() {
    print_header "运行节点"

    # 安装依赖
    if [[ "$OS_TYPE" != "Ubuntu" ]]; then
        install_homebrew
    else
        echo -e "[$(get_timestamp)] ${GREEN}在 Ubuntu 上跳过 Homebrew 安装，使用 apt。${NC}"
    fi
    install_cmake
    install_protobuf
    install_rust
    configure_rust_target
    check_nexus_version # 检查 Nexus CLI 版本，但不立即安装

    # 检查并获取 Node ID
    CONFIG_PATH="$HOME/.nexus/config.json"
    if [[ -f "$CONFIG_PATH" ]]; then
        CURRENT_NODE_ID=$(jq -r .node_id "$CONFIG_PATH" 2>/dev/null)
        if [[ -n "$CURRENT_NODE_ID" && "$CURRENT_NODE_ID" != "null" ]]; then
            echo -e "[$(get_timestamp)] ${GREEN}使用配置文件中的 Node ID：${CURRENT_NODE_ID}${NC}"
            NODE_ID_TO_USE="${CURRENT_NODE_ID}"
        else
            echo -e "[$(get_timestamp)] ${RED}配置文件存在但 Node ID 无效或为空，请检查 $CONFIG_PATH。${NC}"
            exit 1
        fi
    else
        echo -e "[$(get_timestamp)] ${RED}未找到配置文件 $CONFIG_PATH，请先创建并配置 Node ID。${NC}"
        exit 1
    fi

    # 检查 screen 是否安装
    if ! command -v screen &> /dev/null; then
        echo -e "[$(get_timestamp)] ${RED}未找到 screen 命令，正在安装...${NC}"
        if [[ "$OS_TYPE" == "Ubuntu" ]]; then
            sudo apt-get update && sudo apt-get install -y screen || {
                echo -e "[$(get_timestamp)] ${RED}安装 screen 失败，请检查网络连接或权限。${NC}"
                exit 1
            }
        elif [[ "$OS_TYPE" == "macOS" ]]; then
            brew install screen || {
                echo -e "[$(get_timestamp)] ${RED}安装 screen 失败，请检查 Homebrew 安装。${NC}"
                exit 1
            }
        else
            echo -e "[$(get_timestamp)] ${RED}不支持的操作系统，请手动安装 screen。${NC}"
            exit 1
        fi
    fi

    # 定义启动节点的函数
    start_node() {
        # 在启动前清理旧进程
        echo -e "[$(get_timestamp)] ${BLUE}清理旧的 nexus-network 和 bash 进程...${NC}"
        PIDS=$(pgrep -f "nexus-network start --node-id" | tr '\n' ' ' | xargs echo -n)
        if [[ -n "$PIDS" ]]; then
            for pid in $PIDS; do
                if ps -p "$pid" > /dev/null 2>&1; then
                    echo -e "[$(get_timestamp)] ${BLUE}终止旧 Nexus 节点进程 (PID: $pid)...${NC}"
                    kill -9 "$pid" 2>/dev/null || {
                        echo -e "[$(get_timestamp)] ${RED}无法终止 PID $pid 的进程，请检查进程状态。${NC}"
                    }
                else
                    echo -e "[$(get_timestamp)] ${YELLOW}PID $pid 已不存在，跳过。${NC}"
                fi
            done
        fi
        BASH_PIDS=$(pgrep -f "bash -c while true.*nexus-network start --node-id" | tr '\n' ' ' | xargs echo -n)
        if [[ -n "$BASH_PIDS" ]]; then
            for pid in $BASH_PIDS; do
                if ps -p "$pid" > /dev/null 2>&1; then
                    echo -e "[$(get_timestamp)] ${BLUE}终止旧 bash 进程 (PID: $pid)...${NC}"
                    kill -9 "$pid" 2>/dev/null || {
                        echo -e "[$(get_timestamp)] ${RED}无法终止 PID $pid 的 bash 进程，请检查进程状态。${NC}"
                    }
                else
                    echo -e "[$(get_timestamp)] ${YELLOW}PID $pid 已不存在，跳过。${NC}"
                fi
            done
        fi

        # 清理旧的 screen 会话
        if screen -list | grep -q "nexus_node"; then
            echo -e "[$(get_timestamp)] ${BLUE}终止旧的 nexus_node screen 会话...${NC}"
            screen -ls | grep "nexus_node" | awk '{print $1}' | while read -r session; do
                echo -e "[$(get_timestamp)] ${BLUE}终止 screen 会话: $session${NC}"
                screen -S "$session" -X quit 2>/dev/null
            done
        fi

        # 在启动节点前尝试安装/更新 Nexus CLI
        install_nexus_cli

        echo -e "[$(get_timestamp)] ${BLUE}正在启动 Nexus 节点在 screen 会话中...${NC}"
        NEXUS_VERSION=$(nexus-network --version 2>/dev/null || echo "未知版本")
        screen -dmS nexus_node bash -c 'while true; do echo "[$(date "+%Y-%m-%d %H:%M:%S")] Nexus CLI 版本: '"$NEXUS_VERSION"' - 日志:" >> ~/nexus.log; nexus-network start --node-id '"${NODE_ID_TO_USE}"' >> ~/nexus.log 2>&1; sleep 5; done'
        sleep 2
        if screen -list | grep -q "nexus_node"; then
            echo -e "[$(get_timestamp)] ${GREEN}Nexus 节点已在 screen 会话（nexus_node）中启动，日志输出到 ~/nexus.log${NC}"
            NODE_PID=$(pgrep -f "nexus-network start --node-id ${NODE_ID_TO_USE}" | head -n 1)
            if [[ -n "$NODE_PID" ]]; then
                echo -e "[$(get_timestamp)] ${GREEN}Nexus 节点进程 PID: $NODE_PID${NC}"
            else
                echo -e "[$(get_timestamp)] ${RED}无法获取 Nexus 节点 PID，请检查日志：~/nexus.log${NC}"
                cat ~/nexus.log
                exit 1
            fi
        else
            echo -e "[$(get_timestamp)] ${RED}启动 screen 会话失败，请检查日志：~/nexus.log${NC}"
            cat ~/nexus.log
            exit 1
        fi
    }

    # 启动节点
    start_node

    # 循环检测并4小时重启节点
    echo -e "[$(get_timestamp)] ${BLUE}节点将每隔4小时自动重启...${NC}"
    while true; do
        sleep 14400
        echo -e "[$(get_timestamp)] ${BLUE}准备重启节点...${NC}"
        cleanup
        start_node
    done
}

# 直接运行节点
run_node
