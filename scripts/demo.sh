#!/usr/bin/env bash
# scripts/demo.sh —— 一键复现演示（Linux / macOS）
#
# ⚠️ 未在开发机验证（本项目在 Windows 上开发）。
# 说明：docs/SCRIPTS.md 第 3 节

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

OUT_DIR="$REPO_ROOT/demo/out"
mkdir -p "$OUT_DIR"
LOG_FILE="$OUT_DIR/demo-$(date +%Y%m%d-%H%M%S).log"

step() {
  echo
  echo "── [$1] $2"
}

run() {
  echo "    \$ $*"
  # 同时输出到终端与日志
  "$@" 2>&1 | tee -a "$LOG_FILE"
}

echo "moonbit-eigen 演示"
echo "仓库：$REPO_ROOT"
echo "日志：$LOG_FILE"

step 1 "检查工具链"
if ! command -v moon >/dev/null 2>&1; then
  echo "未找到 moon。安装：curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash" >&2
  exit 1
fi
run moon version --all

step 2 "获取第三方依赖（Eigen，按固定版本）"
run bash scripts/fetch-eigen.sh

step 3 "类型检查"
run moon check --target native

step 4 "运行测试"
run moon test --target native selftest
run moon test --target native src

step 5 "运行示例：解线性方程组"
run moon run examples/solve --target native

step 6 "运行示例：一元线性回归"
run moon run examples/linreg --target native

step 7 "运行示例：与纯 MoonBit 实现对拍"
run moon run examples/crosscheck --target native

echo
echo "演示完成，全部步骤成功。"
echo "日志已保存：$LOG_FILE"
