#!/usr/bin/env bash
# scripts/build-shim.sh —— Plan B：把 C++ 胶水预编译成目标文件（Linux / macOS）
#
# 与 scripts/build-shim.ps1 等价。使用时机与完整步骤见 docs/PLAN_B.md。
#
# 用法：
#   bash scripts/build-shim.sh
#
# 产出：build/eigen_shim.o

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

CXX="${CXX:-}"
OUT_DIR="${OUT_DIR:-build}"

# $MOON_HOME 默认是 ~/.moon
MOON_HOME_DIR="${MOON_HOME:-$HOME/.moon}"
MOON_INCLUDE="$MOON_HOME_DIR/include"

# ── 前置检查 ──────────────────────────────────────────────────────────────────
if [ ! -f "$MOON_INCLUDE/moonbit.h" ]; then
  echo "未找到 moonbit.h：$MOON_INCLUDE/moonbit.h" >&2
  echo "请先安装 MoonBit 工具链，或设置 MOON_HOME。" >&2
  exit 1
fi

if [ -z "$CXX" ]; then
  if command -v clang++ >/dev/null 2>&1; then CXX=clang++
  elif command -v g++ >/dev/null 2>&1; then CXX=g++
  else
    echo "未找到 clang++ 或 g++。" >&2
    exit 1
  fi
fi

if [ ! -f "src/third_party/eigen/Eigen/Dense" ]; then
  echo "未找到 Eigen。请先运行：bash scripts/fetch-eigen.sh" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "编译 C++ 胶水（Plan B）"
echo "  编译器   : $CXX"
echo "  moonbit.h: $MOON_INCLUDE"
echo "  输出     : $OUT_DIR/eigen_shim.o"
echo

# 与 src/moon.pkg 里 Plan A 的选项保持一致，避免两条路径行为不同。
"$CXX" -c -std=c++17 -O1 -I"$MOON_INCLUDE" \
  src/eigen_shim.cpp -o "$OUT_DIR/eigen_shim.o"

echo
echo "完成：$OUT_DIR/eigen_shim.o"
echo "下一步：按 docs/PLAN_B.md 把 src/moon.pkg 换成 Plan B 版本（Linux 需要 -lstdc++），然后："
echo "  moon test --target native"
echo
echo "注意：cc-link-flags 里的相对路径按 pwd 解析（moon issue #586），"
echo "      所以务必在模块根目录执行 moon 命令。"
