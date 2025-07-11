#!/bin/bash

set -e  # 出错即退出
set -u  # 使用未定义变量时报错

PROJECT_DIR="$HOME/infernet-container-starter/deploy"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yaml"

echo "🚀 切换到部署目录：$PROJECT_DIR"
cd "$PROJECT_DIR" || { echo "❌ 目录不存在：$PROJECT_DIR"; exit 1; }

echo "🔍 检查并更新 docker-compose.yml 中的 depends_on 设置..."

# 检查并修改 depends_on 行
if grep -q 'depends_on: \[ redis, infernet-anvil \]' "$COMPOSE_FILE"; then
  sed -i.bak 's/depends_on: \[ redis, infernet-anvil \]/depends_on: [ redis ]/' "$COMPOSE_FILE"
  echo "✅ 已修改 depends_on 配置。备份文件保存在：docker-compose.yml.bak"
else
  echo "✅ depends_on 配置已正确，无需修改。"
fi

echo "🧹 停止并清理当前 Docker Compose 服务..."
docker compose down || { echo "⚠️ docker compose down 执行失败，继续执行下一步..."; }

echo "⚙️ 启动指定服务：node、redis、fluentbit"
docker compose up node redis fluentbit
