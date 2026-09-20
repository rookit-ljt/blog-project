#!/usr/bin/env bash
set -e

echo "======================================"
echo "🚀 开始部署 rookie_L 个人博客..."
echo "======================================"

# 确保在脚本所在目录
cd "$(dirname "$0")"

# 检查 git 变更
echo "📥 1. 拉取最新代码..."
git pull origin main

# 构建并启动容器
echo "🐳 2. 构建并重启 Docker 容器..."
docker compose -f docker-compose.prod.yaml up -d --build

# 清理无用的虚悬镜像
echo "🧹 3. 清理无用 Docker 镜像..."
docker image prune -f

echo "======================================"
echo "✅ 部署完成！容器运行状态："
echo "======================================"
docker compose -f docker-compose.prod.yaml ps
