#!/usr/bin/env bash
# scripts/fetch-eigen.sh —— 获取 Eigen 源码（Linux / macOS）
#
# ⚠️ 未在开发机验证（本项目在 Windows 上开发）。
# 说明：docs/SCRIPTS.md 第 1 节

set -euo pipefail

# 固定版本：不要用 master。升级时改这里并记入 docs/DECISIONS.md。
EIGEN_REF="${EIGEN_REF:-3.4.0}"

# 路径按"脚本所在目录的上一级"解析，避免受调用方 pwd 影响。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TARGET="$REPO_ROOT/src/third_party/eigen"

if [ -f "$TARGET/Eigen/Dense" ]; then
  echo "Eigen 已存在于 $TARGET，跳过下载。"
  exit 0
fi

echo "正在获取 Eigen $EIGEN_REF → $TARGET"
mkdir -p "$(dirname "$TARGET")"

# 浅克隆 + 检出固定 tag，避免拉取完整历史。
git clone --depth 1 --branch "$EIGEN_REF" https://gitlab.com/libeigen/eigen.git "$TARGET"

if [ ! -f "$TARGET/Eigen/Dense" ]; then
  echo "错误：下载完成但未找到 Eigen/Dense，目录结构可能与预期不符。" >&2
  exit 1
fi

echo "完成。Eigen $EIGEN_REF 已就位。"
