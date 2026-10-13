#!/usr/bin/env bash
# scripts/run-asan.sh —— 用 AddressSanitizer / UBSan 跑测试（Linux / macOS，GCC 或 Clang）
#
# ⚠️ 平台说明
#   · **Windows 上请用 scripts/run-asan.ps1**（已实测通过）。
#     本项目的开发与验证环境是 Windows + MSVC，那边的配方（含 0xc0000135
#     这个坑与防假绿断言）见 docs/PITFALLS.md 第 12 节。
#   · 本脚本是给 Linux/macOS 用的，**在当前开发机上无法验证**（没有可用的
#     bash 与 GCC 环境）。它的验证状态如实标注为「未验证」。
#     它被设计成**宁可失败也不假绿**：任何一步对不上就直接报错退出。
#
# ── 为什么第 1 周就该有这个 ────────────────────────────────────────────────
# 跨语言边界的所有权类 bug 大多"运行时才炸、且不炸在出错点"
# —— 悬垂引用、双重释放、越界写。等末期再补验证网，
# 积累的 bug 已经互相掩盖，排查成本指数上升。
#
# ── 历史教训（这个脚本的前一版会「假绿」）───────────────────────────────────
# 前一版用 python3 正则替换 src/moon.pkg 里的 cc-flags / cc-link-flags，
# 但那两个字段**在本仓库里刻意没有设置**（留给 moon 自动发现工具链），
# 于是替换静默失败，脚本照样报告「sanitizer 运行结束（无输出即无问题）」。
# **没生效却报告成功，比没有 ASan 更危险。**
# 本版因此有两道断言：注入必须真的改到文件；产物里必须真的出现 __asan。
#
# 用法：
#   bash scripts/run-asan.sh
#
# 实现思路：把 stub-cc-flags 从 MSVC 语法换成 GCC/Clang 语法并加上 sanitizer
# （MSVC 的 /EHsc /utf-8 在 GCC 上不被识别，必须整体替换）。
# 生态先例 illusory0x0/qpainter 用的正是 "-fsanitize=address -fsanitize=undefined"。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

if [ ! -f "src/third_party/eigen/Eigen/Dense" ]; then
  echo "错误：未找到 Eigen。请先运行 bash scripts/fetch-eigen.sh" >&2
  exit 1
fi

PKG="src/moon.pkg"
BACKUP="$(mktemp)"
cp "$PKG" "$BACKUP"

restore() {
  cp "$BACKUP" "$PKG"
  rm -f "$BACKUP"
  echo "  （src/moon.pkg 已还原）"
}
trap restore EXIT

# ── 第一道断言：必须先确认目标字段存在，否则立刻失败 ─────────────────────────
if ! grep -q '"stub-cc-flags"' "$PKG"; then
  echo "错误：src/moon.pkg 里找不到 \"stub-cc-flags\" 字段。" >&2
  echo "      无法注入 sanitizer —— 拒绝在'什么都没做'的情况下报告成功。" >&2
  exit 1
fi

SAN="-fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer"
GCC_FLAGS="-std=c++17 -fexceptions -O1 ${SAN}"

# 整体替换 MSVC 语法（/EHsc /utf-8 等 GCC 不认）
sed -i.bak -E 's|"stub-cc-flags"[[:space:]]*:[[:space:]]*"[^"]*"|"stub-cc-flags": "'"$GCC_FLAGS"'"|' "$PKG"
# GCC 驱动不会自动链 libstdc++，必须显式加；sanitizer 也要参与链接
sed -i.bak -E 's|"cc-link-flags"[[:space:]]*:[[:space:]]*"[^"]*"|"cc-link-flags": "-lstdc++ '"$SAN"'"|' "$PKG"
rm -f "${PKG}.bak"

# ── 第二道断言：替换必须真的生效 ─────────────────────────────────────────────
if ! grep -q 'fsanitize=address' "$PKG"; then
  echo "错误：注入后 moon.pkg 里仍然没有 sanitizer 选项，替换未生效。" >&2
  exit 1
fi
echo "已注入 sanitizer 选项：$GCC_FLAGS"

echo "=== 以 ASan/UBSan 运行测试 ==="
moon test --target native src
moon test --target native selftest

# ── 第三道断言：产物里必须真的出现 ASan 符号（防假绿）───────────────────────
echo "=== 确认 ASan 真的生效（而非假绿）==="
FOUND=0
while IFS= read -r exe; do
  if grep -qa '__asan' "$exe" 2>/dev/null; then
    echo "  已确认：$exe 含有 __asan 符号"
    FOUND=1
    break
  fi
done < <(find _build -name '*.exe' -o -name '*test*' -type f 2>/dev/null | sort -u)

if [ "$FOUND" -eq 0 ]; then
  echo "错误：测试虽然通过，但产物里没有 ASan 痕迹 —— 这是假绿。" >&2
  echo "      本次运行不能作为内存安全证据。" >&2
  exit 1
fi

echo "=== sanitizer 测试通过 ==="
