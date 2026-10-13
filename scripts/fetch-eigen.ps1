# scripts/fetch-eigen.ps1 —— 按固定版本获取 Eigen（Windows）
#
# 为什么用脚本而不是直接入库？
#   · Eigen 是 header-only 的目录树（数百个文件），入库会让仓库体积和审查负担陡增；
#   · 官方 agent skill 建议"钉住上游版本 + 可重复脚本"（pinned revision + repeatable script）；
#   · 版本固定后，CI 与本地拿到的是同一份代码。
#
# 用法：
#   pwsh -File scripts/fetch-eigen.ps1
#
# 依赖：git（本机已具备）。

param(
  # 固定版本：不要用 master。升级时改这里并记入 docs/DECISIONS.md。
  [string]$Ref = "3.4.0",
  [string]$Destination = "src/third_party/eigen"
)

$ErrorActionPreference = "Stop"

# 路径按"脚本所在目录的上一级"解析，避免受调用方 pwd 影响。
$repoRoot = Split-Path -Parent $PSScriptRoot
$target = Join-Path $repoRoot $Destination

if (Test-Path -LiteralPath (Join-Path $target "Eigen" "Dense")) {
  Write-Host "Eigen 已存在于 $target，跳过下载。"
  exit 0
}

Write-Host "正在获取 Eigen $Ref → $target"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null

# 浅克隆 + 检出固定 tag，避免拉取完整历史。
git clone --depth 1 --branch $Ref https://gitlab.com/libeigen/eigen.git $target

if (-not (Test-Path -LiteralPath (Join-Path $target "Eigen" "Dense"))) {
  Write-Error "下载完成但未找到 Eigen/Dense，Eigen 目录结构可能与预期不符。"
  exit 1
}

Write-Host "完成。Eigen $Ref 已就位。"
