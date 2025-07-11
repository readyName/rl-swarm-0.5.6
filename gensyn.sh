#!/bin/bash
set -euo pipefail

log_file="./deploy_rl_swarm_0.5.3.log"
max_retries=10
retry_count=0

info() {
    echo -e "[$(date +"%Y-%m-%d %T")] [INFO] $*" | tee -a "$log_file"
}

error() {
    echo -e "[$(date +"%Y-%m-%d %T")] [ERROR] $*" >&2 | tee -a "$log_file"
    if [ $retry_count -lt $max_retries ]; then
        retry_count=$((retry_count+1))
        info "自动重试 ($retry_count/$max_retries)..."
        exec "$0" "$@"
    else
        echo -e "[$(date +"%Y-%m-%d %T")] [ERROR] 达到最大重试次数 ($max_retries 次)，请手动重启 Docker 并检查环境" >&2 | tee -a "$log_file"
        exit 1
    fi
}

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装，请先安装 Docker (https://www.docker.com)"
    fi
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose 未安装，请先安装 Docker Compose"
    fi
}

# 打开 Docker
start_docker() {
    info "正在启动 Docker..."
    if ! open -a Docker; then
        error "无法启动 Docker 应用，请检查 Docker 是否安装或手动启动"
    fi
    # 等待 Docker 启动
    info "等待 Docker 启动完成..."
    sleep 10
    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        error "Docker 未正常运行，请检查 Docker 状态"
    fi
}

# 运行 Docker Compose 容器
run_docker_compose() {
    local attempt=1
    local max_attempts=$max_retries
    while [ $attempt -le $max_attempts ]; do
        info "尝试运行容器 swarm-cpu (第 $attempt 次)..."
        if docker-compose up swarm-cpu; then
            info "容器 swarm-cpu 运行成功"
            return 0
        else
            info "Docker 构建失败，重试中..."
            sleep 2
            ((attempt++))
        fi
    done
    error "Docker 构建超过最大重试次数 ($max_attempts 次)"
}

# 主逻辑
main() {
    # 检查 Docker 环境
    check_docker

    # 启动 Docker
    start_docker

    # 进入目录
    info "进入 rl-swarm-0.5.3 目录..."
    cd ~/rl-swarm-0.5.3 || error "进入 rl-swarm-0.5.3 目录失败"

    # 运行容器
    info "🚀 运行 swarm-cpu 容器..."
    run_docker_compose
}

# 执行主逻辑
main "$@"
