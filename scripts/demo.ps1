# scripts/demo.ps1 —— 一键复现演示（8 步）
#
# 工具链 → 类型检查 → FFI 自检 → 取 Eigen → 完整测试 → 三个示例。
# 输出与日志落 demo/out/。说明：docs/SCRIPTS.md 第 3 节

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$outDir = Join-Path $root 'demo\out'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logFile = Join-Path $outDir "demo-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Step($n, $text) {
  Write-Host ""
  Write-Host "── [$n] $text" -ForegroundColor Cyan
}
function Ok($msg) { Write-Host "    [OK] $msg" -ForegroundColor Green }

# 执行一条命令并记录输出。
#
# ⚠️ 两个坑（都实测踩过，详见 docs/PITFALLS.md 第 11 节）：
#
# 1) 不要把命令拼成字符串再用 Invoke-Expression 执行。
#    早期版本那样写，其中一条因为变量插值丢了变成 `& '' ...`；
#    而"命令找不到"**不会更新 $LASTEXITCODE**，于是上一条成功命令的 0
#    被当成了"这条也成功" —— 整步被静默跳过，演示却报告"全部步骤成功"。
#    现在改为「可执行文件 + 参数数组」，并在执行前显式确认可执行文件存在。
#
# 2) 原生命令写 stderr 时，若 $ErrorActionPreference = 'Stop' 会变成终止性错误。
#    这里临时切回 Continue，并以 $LASTEXITCODE 作为唯一判据。
function Run([string]$exe, [string[]]$cmdArgs, [switch]$RetrySpawn) {
  if (-not (Get-Command $exe -ErrorAction SilentlyContinue) -and
      -not (Test-Path -LiteralPath $exe)) {
    throw "找不到可执行文件：$exe"
  }

  $attempts = if ($RetrySpawn) { 2 } else { 1 }
  for ($i = 1; $i -le $attempts; $i++) {
    Write-Host ("    $ {0} {1}" -f $exe, ($cmdArgs -join ' ')) -ForegroundColor DarkGray

    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $exe @cmdArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $saved

    $output | ForEach-Object { Write-Host "    $_" }
    $output | Out-File -FilePath $logFile -Append -Encoding utf8
    if ($code -eq 0) { return }

    # Windows 上刚构建出的 .exe 偶发被杀软扫描暂锁，moon 会报
    # "Failed to spawn command" —— 这不是测试失败。
    # 只在**识别出这种特定情形**时重试一次，避免掩盖真正的失败。
    if ($RetrySpawn -and $i -lt $attempts -and
        (($output | Out-String) -match 'Failed to spawn')) {
      Write-Host "    （新建的 .exe 可能被杀软暂锁，重试一次）" -ForegroundColor DarkGray
      Start-Sleep -Seconds 2
      continue
    }
    break
  }

  Write-Host ""
  Write-Host "演示中止：上一条命令失败（exit $code）" -ForegroundColor Red
  Write-Host "日志：$logFile"
  exit 1
}

Write-Host "moonbit-eigen 一键复现演示" -ForegroundColor Green
Write-Host "仓库：$root"
Write-Host "日志：$logFile"

# ── Step 1：工具链 ───────────────────────────────────────────────────────────
Step 1 "检查工具链（moon + MSVC）"
$moon = (Get-Command moon -ErrorAction SilentlyContinue).Source
if (-not $moon) {
  $fallback = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'
  if (Test-Path -LiteralPath $fallback) {
    $moon = $fallback
    Ok "moon 不在 PATH，改用 $fallback"
  } else {
    Write-Host "未找到 moon。安装方式：" -ForegroundColor Red
    Write-Host '  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
    Write-Host '  irm https://cli.moonbitlang.com/install/powershell.ps1 | iex'
    exit 1
  }
}
Run $moon @('version')

# MSVC：moon 自己是用 vswhere 发现的，装好的 VS Build Tools
# **不会**把 cl.exe 放进 PATH —— 所以这里不能只查 PATH，否则会误报"没有编译器"。
$hasCxx = $false
foreach ($c in 'cl', 'clang-cl') {
  $p = Get-Command $c -ErrorAction SilentlyContinue
  if ($p) { Ok "$c -> $($p.Source)"; $hasCxx = $true }
}
if (-not $hasCxx) {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (Test-Path -LiteralPath $vswhere) {
    $installs = & $vswhere -products * `
      -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
      -property installationPath 2>$null
    foreach ($ip in $installs) {
      Ok "MSVC（经 vswhere 发现，未在 PATH 上）-> $ip"
      $hasCxx = $true
    }
  }
}
if (-not $hasCxx) {
  Write-Host "    未找到 MSVC 兼容工具链。" -ForegroundColor Yellow
  Write-Host "    Windows 上 native 后端只接受 MSVC（MinGW 被官方排除）。" -ForegroundColor Yellow
}

# ── Step 2：类型检查 ─────────────────────────────────────────────────────────
Step 2 "类型检查（不需要 C 编译器）"
Run $moon @('check', '--target', 'native')

# ── Step 3：FFI 机制自检 ─────────────────────────────────────────────────────
# 这一步**故意放在取 Eigen 之前**：它零第三方依赖，
# 因此"MoonBit 能不能调用 C++"这个机制问题可以独立得出结论，
# 不被第三方依赖的下载问题干扰。
Step 3 "FFI 机制自检（零第三方依赖 —— Plan A 的结论在这里出来）"
Run $moon @('test', '--target', 'native', 'selftest') -RetrySpawn

# ── Step 4：取 Eigen ─────────────────────────────────────────────────────────
Step 4 "获取第三方依赖（Eigen，按固定版本）"
Run 'powershell' @('-ExecutionPolicy', 'Bypass', '-File', 'scripts\fetch-eigen.ps1')

# ── Step 5：完整测试 ─────────────────────────────────────────────────────────
# ⚠️ 必须带包名：整模块调用时，声明了 native-stub 的库包会被额外尝试
#    链接成 .exe，而库包没有 main → LNK2019（见 docs/PITFALLS.md 第 10.2 节）。
Step 5 "完整测试（Eigen 绑定，18 个）"
Run $moon @('test', '--target', 'native', 'src') -RetrySpawn

# ── Step 6-8：示例 ───────────────────────────────────────────────────────────
Step 6 "运行示例：解线性方程组"
Run $moon @('run', 'examples/solve', '--target', 'native')

Step 7 "运行示例：一元线性回归"
Run $moon @('run', 'examples/linreg', '--target', 'native')

Step 8 "运行示例：与纯 MoonBit 实现对拍"
Run $moon @('run', 'examples/crosscheck', '--target', 'native')

Write-Host ""
Write-Host "演示完成，全部 8 个步骤成功。" -ForegroundColor Green
Write-Host "日志已保存：$logFile"
exit 0
