#!/usr/bin/env bash
set -e

# 确保在脚本所在目录
cd "$(dirname "$0")"

# 1. 获取远端最新提交信息
git fetch origin main > /dev/null 2>&1

LOCAL_COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git rev-parse origin/main)

# 2. 对比版本：若无更新且未传 --force 参数，直接秒级退出，避免无谓消耗服务器 CPU
if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ] && [ "$1" != "--force" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚡ 代码已是最新 ($(git rev-parse --short HEAD))，无需重新构建。"
    exit 0
fi

echo "======================================"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🚀 检测到新提交，开始自动更新博客..."
echo "======================================"

# 3. 合并远端最新代码
echo "📥 1. 拉取最新代码..."
git pull origin main

# 4. 构建并平滑重启容器
echo "🐳 2. 构建并重启 Docker 容器..."
docker compose -f docker-compose.prod.yaml up -d --build

# 5. 清理无用 Docker 镜像
echo "🧹 3. 清理无用虚悬镜像..."
docker image prune -f

echo "======================================"
echo "✅ 博客已自动更新上线！当前版本: $(git rev-parse --short HEAD)"
echo "======================================"
docker compose -f docker-compose.prod.yaml ps
