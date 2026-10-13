#!/usr/bin/env bash
# scripts/run-asan.sh —— 用 AddressSanitizer / UBSan 跑测试
#
# 为什么第 1 周就要有这个脚本（官方 agent skill 的建议）：
#   跨语言边界的所有权类 bug 大多"运行时才炸、且不炸在出错点"
#   —— 悬垂引用、双重释放、越界写。等到项目末期再补验证网，
#   积累的 bug 已经互相掩盖，排查成本指数上升。
#
# 用法：
#   bash scripts/run-asan.sh
#
# ⚠️ 未验证：本脚本尚未实跑过。W1 的任务之一就是让它变绿。
#    实现思路：把 -fsanitize=address,undefined 通过 cc-flags 注入构建，
#    再跑 moon test --target native selftest
moon test --target native src。
#    生态先例 illusory0x0/qpainter 的配置里用的正是
#    "-fsanitize=address -fsanitize=undefined"。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

if [ ! -f "src/third_party/eigen/Eigen/Dense" ]; then
  echo "错误：未找到 Eigen。请先运行 bash scripts/fetch-eigen.sh" >&2
  exit 1
fi

# ASan 需要链接时也带 sanitizer 运行时，因此 cc-flags 与 cc-link-flags 都要注入。
# 注意：直接改 src/moon.pkg 会污染仓库状态，所以这里先改、跑完再还原
# （用 trap 保证异常退出也能还原）。
PKG="src/moon.pkg"
BACKUP="$(mktemp)"
cp "$PKG" "$BACKUP"

restore() {
  cp "$BACKUP" "$PKG"
  rm -f "$BACKUP"
}
trap restore EXIT

# 在 cc-flags / cc-link-flags 上追加 sanitizer 选项。
# 这是文本替换而非结构化编辑 —— 若 moon.pkg 结构调整，本脚本需要同步更新。
python3 - "$PKG" <<'PY'
import sys, re, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
san = "-fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer"
s = re.sub(r'("cc-flags":\s*")', r'\1' + san + " ", s, count=1)
s = re.sub(r'("cc-link-flags":\s*")', r'\1' + san + " ", s, count=1)
p.write_text(s, encoding="utf-8")
print("已注入 sanitizer 选项")
PY

echo "=== 以 ASan/UBSan 运行测试 ==="
moon test --target native selftest
moon test --target native src

echo "=== sanitizer 运行结束（无输出即无问题）==="
