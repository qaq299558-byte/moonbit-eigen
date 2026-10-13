# scripts/build-shim.ps1 —— Plan B：把 C++ 胶水预编译成目标文件（Windows）
#
# 什么时候需要它？
#   当 src/moon.pkg 的 "native-stub": ["eigen_shim.cpp"]（Plan A）失败时。
#   官方只把 native-stub 定义为 "C stub source files"，对 .cpp 无明文承诺；
#   生态里唯一的 C++ 先例（illusory0x0/qpainter）走的正是这条路：
#   在 moon 之外先把 C++ 编好，再用 cc-link-flags 链进来。
#   完整步骤见 docs/PLAN_B.md。
#
# ⚠️ 状态说明（2026-10-13）：**Plan A 已实测成立，因此本脚本不是必需路径。**
#    它已按本机环境（VS Build Tools 装在 E:\VSBuildTools、cl 不在 PATH 上）
#    修正并实测可编译通过，作为备用手段保留。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\build-shim.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\build-shim.ps1 -OutDir build
#
# 产出：build/eigen_shim.obj
# 之后把 src/moon.pkg 换成 docs/PLAN_B.md 里给出的 Plan B 版本。
#
# 早期版本的三个错误（已修）：
#   1. 默认 -Cc clang-cl —— 本机没装 LLVM，且 cl.exe 并不在 PATH 上，
#      于是脚本会误报"未找到编译器"并建议你去装 LLVM（其实 MSVC 已装好）。
#   2. 直接用 cl.exe —— 不经过 vcvars 的话，cl 找不到标准库头文件。
#   3. 缺 /utf-8 —— 而 src/eigen_shim.cpp 里有中文字符串，
#      少了它会按系统代码页解释，错误信息变乱码。

param(
  # 留空 = 自动探测：优先用 vswhere 找到的 MSVC，其次 PATH 上的 cl / clang-cl。
  [string]$Cc = "",
  [string]$OutDir = "build",
  # 留空 = 自动探测 vcvars64.bat
  [string]$VcVars = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$moonHome = if ($env:MOON_HOME) { $env:MOON_HOME } else { Join-Path $env:USERPROFILE '.moon' }
$moonInclude = Join-Path $moonHome 'include'
$moonbitHeader = Join-Path $moonInclude 'moonbit.h'

# ── 前置检查（失败就给出可操作的提示，而不是让编译器报一堆无关错误）────────────
if (-not (Test-Path -LiteralPath $moonbitHeader)) {
  Write-Host "未找到 moonbit.h：$moonbitHeader" -ForegroundColor Red
  Write-Host "请先安装 MoonBit 工具链，或设置 MOON_HOME 指向正确位置。"
  exit 1
}

if (-not (Test-Path -LiteralPath (Join-Path $root 'src\third_party\eigen\Eigen\Dense'))) {
  Write-Host "未找到 Eigen。请先运行：powershell -ExecutionPolicy Bypass -File scripts\fetch-eigen.ps1" -ForegroundColor Red
  exit 1
}

# ── 探测工具链 ──────────────────────────────────────────────────────────────
# 关键点：Windows 上 moon 是通过 vswhere 发现 MSVC 的，装好的 VS Build Tools
# **不会**把 cl.exe 放进 PATH。所以只查 PATH 会误报"未找到编译器"。

$vcvarsPath = $null
$vsInstall = $null

if ($VcVars) {
  $vcvarsPath = $VcVars
} else {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (Test-Path -LiteralPath $vswhere) {
    $installs = & $vswhere -products * `
      -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
      -property installationPath 2>$null
    foreach ($ip in $installs) {
      $cand = Join-Path $ip 'VC\Auxiliary\Build\vcvars64.bat'
      if (Test-Path -LiteralPath $cand) { $vcvarsPath = $cand; $vsInstall = $ip; break }
    }
  }
}

$useVcVars = $false
if (-not $Cc) {
  if ($vcvarsPath) {
    $Cc = 'cl'
    $useVcVars = $true
  } else {
    foreach ($c in 'cl', 'clang-cl') {
      if (Get-Command $c -ErrorAction SilentlyContinue) { $Cc = $c; break }
    }
  }
}

if (-not $Cc) {
  Write-Host "未找到 MSVC 兼容的 C++ 编译器。" -ForegroundColor Red
  Write-Host "Windows 上 native 后端只接受 MSVC 兼容工具链（MinGW 被官方排除）。"
  Write-Host "装 VS Build Tools 的 C++ 工作负载，或安装 LLVM，然后把 cl.exe 放进 PATH。"
  exit 1
}

if (-not $useVcVars -and -not (Get-Command $Cc -ErrorAction SilentlyContinue)) {
  # 显式指定了编译器但不在 PATH 上 —— 当作路径处理
  if (-not (Test-Path -LiteralPath $Cc)) {
    Write-Host "未找到编译器：$Cc" -ForegroundColor Red
    exit 1
  }
}

New-Item -ItemType Directory -Force -Path (Join-Path $root $OutDir) | Out-Null
$obj = Join-Path $root (Join-Path $OutDir 'eigen_shim.obj')

Write-Host "编译 C++ 胶水（Plan B）"
if ($vsInstall) { Write-Host "  VS 安装  : $vsInstall" }
Write-Host "  编译器   : $Cc$(if ($useVcVars) { '（经 vcvars64 初始化环境）' })"
Write-Host "  moonbit.h: $moonbitHeader"
Write-Host "  输出     : $obj"
Write-Host ""

# 编译选项与 src/moon.pkg 里 Plan A 的 stub-cc-flags 对齐：
#   /EHsc  C++ 异常（胶水层要靠它把异常挡在 ABI 边界内）
#   /utf-8 源码与执行字符集都是 UTF-8（错误信息里有中文，必须加）
#   /bigobj  Eigen 模板实例化会产生大量 section
# 注意 moon 在 Plan A 里会自动加 -I，我们自己编译要手动加。
$clArgs = '/c /std:c++17 /EHsc /utf-8 /bigobj /O1 ' +
          "/I`"$moonInclude`" " +
          "`"src\eigen_shim.cpp`" " +
          "/Fo`"$obj`""

# ⚠️ 编译器输出一律让 cmd.exe 自己重定向到文件，再由 PowerShell 读出来打印。
#
# 为什么不直接 `2>&1 | ForEach-Object`：PowerShell 5.1 下把原生命令的 stderr
# 接进管道会产生 ErrorRecord（NativeCommandError）。配合脚本开头的
# $ErrorActionPreference = 'Stop' 会变成**终止性错误**；即使临时切回 Continue，
# 打印出来也只是 "System.Management.Automation.RemoteException" 这种无用信息，
# 而且 `powershell -File` 还会因此返回非零退出码。
# 而 cl 一定会把版权横幅写到 stderr —— 必然触发。
# 本项目被这个坑咬了三次（fetch-eigen / demo / 本脚本），见 PITFALLS 第 11 节。
# 把重定向交给 cmd.exe，PowerShell 就完全看不到 stderr 了。
$tmpLog = Join-Path $env:TEMP ("eigen-shim-build-" + [guid]::NewGuid().ToString('N') + ".log")
if ($useVcVars) {
  # 在同一个 cmd 会话里先初始化 vcvars，再调用 cl —— 这是拿到
  # INCLUDE / LIB 环境变量的标准做法。
  & cmd.exe /c "`"$vcvarsPath`" x64 >nul 2>&1 && $Cc $clArgs > `"$tmpLog`" 2>&1"
} else {
  & cmd.exe /c "$Cc $clArgs > `"$tmpLog`" 2>&1"
}
$exit = $LASTEXITCODE
if (Test-Path -LiteralPath $tmpLog) {
  Get-Content -LiteralPath $tmpLog | ForEach-Object { "    $_" }
  Remove-Item -LiteralPath $tmpLog -Force -ErrorAction SilentlyContinue
}

if ($exit -ne 0 -or -not (Test-Path -LiteralPath $obj)) {
  Write-Host ""
  Write-Host "编译失败（退出码 $exit）。常见原因：" -ForegroundColor Red
  Write-Host "  · Eigen 相对包含失败 → 在 src/eigen_shim.hpp 里改用绝对路径，或加 /I 指向 src"
  Write-Host "  · C++ 标准太低 → 确认 /std:c++17 生效"
  exit 1
}

Write-Host "完成：$obj" -ForegroundColor Green
Write-Host ""
Write-Host "下一步：按 docs/PLAN_B.md 把 src/moon.pkg 换成 Plan B 版本，然后跑："
Write-Host "  moon test --target native src"
Write-Host ""
Write-Host "注意：cc-link-flags 里的相对路径按 pwd 解析（moon issue #586），"
Write-Host "      所以务必在模块根目录（$root）执行 moon 命令。

exit 0"
