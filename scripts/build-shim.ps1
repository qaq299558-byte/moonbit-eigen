# scripts/build-shim.ps1 —— Plan B：把 C++ 胶水预编译成目标文件（Windows）
#
# 什么时候需要它？
#   当 src/moon.pkg 的 "native-stub": ["eigen_shim.cpp"]（Plan A）失败时。
#   官方只把 native-stub 定义为 "C stub source files"，对 .cpp 无明文承诺；
#   生态里唯一的 C++ 先例（illusory0x0/qpainter）走的正是这条路：
#   在 moon 之外先把 C++ 编好，再用 cc-link-flags 链进来。
#   完整步骤见 docs/PLAN_B.md。
#
# 用法：
#   powershell -File scripts/build-shim.ps1
#
# 产出：build/eigen_shim.obj
# 之后把 src/moon.pkg 换成 docs/PLAN_B.md 里给出的 Plan B 版本。

param(
  # Windows 上只能是 MSVC 兼容驱动（cl.exe / clang-cl.exe），MinGW 被官方排除
  [string]$Cc = "clang-cl",
  [string]$OutDir = "build"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# $MOON_HOME 默认是 ~/.moon；moonbit.h 就在它的 include 子目录里。
$moonHome = if ($env:MOON_HOME) { $env:MOON_HOME } else { Join-Path $env:USERPROFILE '.moon' }
$moonInclude = Join-Path $moonHome 'include'
$moonbitHeader = Join-Path $moonInclude 'moonbit.h'

# ── 前置检查（失败就给出可操作的提示，而不是让编译器报一堆无关错误）────────────
if (-not (Test-Path -LiteralPath $moonbitHeader)) {
  Write-Host "未找到 moonbit.h：$moonbitHeader" -ForegroundColor Red
  Write-Host "请先安装 MoonBit 工具链，或设置 MOON_HOME 指向正确位置。"
  exit 1
}

$compiler = Get-Command $Cc -ErrorAction SilentlyContinue
if (-not $compiler) {
  Write-Host "未找到编译器：$Cc" -ForegroundColor Red
  Write-Host "Windows 上请安装 LLVM（clang-cl）或 VS Build Tools（cl）："
  Write-Host "  winget install LLVM.LLVM"
  exit 1
}

if (-not (Test-Path -LiteralPath (Join-Path $root 'src\third_party\eigen\Eigen\Dense'))) {
  Write-Host "未找到 Eigen。请先运行：powershell -File scripts/fetch-eigen.ps1" -ForegroundColor Red
  exit 1
}

New-Item -ItemType Directory -Force -Path (Join-Path $root $OutDir) | Out-Null
$obj = Join-Path $OutDir 'eigen_shim.obj'

Write-Host "编译 C++ 胶水（Plan B）"
Write-Host "  编译器 : $($compiler.Source)"
Write-Host "  moonbit.h: $moonbitHeader"
Write-Host "  输出   : $obj"
Write-Host ""

# 与 src/moon.pkg 里 Plan A 的编译选项保持一致，避免两种路径行为不同。
# moonbit.h 需要显式 -I：moon 在 Plan A 里会自动加，我们自己编译时要手动加。
& $compiler /c /std:c++17 /EHsc /bigobj /O1 "/I$moonInclude" `
  "src\eigen_shim.cpp" "/Fo$obj"

if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $obj)) {
  Write-Host ""
  Write-Host "编译失败。常见原因：" -ForegroundColor Red
  Write-Host "  · Eigen 相对包含失败 → 在 src/eigen_shim.hpp 里改用绝对路径，或加 /I 指向 src"
  Write-Host "  · C++ 标准太低 → 确认 /std:c++17 生效"
  exit 1
}

Write-Host ""
Write-Host "完成：$obj" -ForegroundColor Green
Write-Host "下一步：按 docs/PLAN_B.md 把 src/moon.pkg 换成 Plan B 版本，然后跑："
Write-Host "  moon test --target native"
Write-Host ""
Write-Host "注意：cc-link-flags 里的相对路径按 pwd 解析（moon issue #586），"
Write-Host "      所以务必在模块根目录（$root）执行 moon 命令。"
