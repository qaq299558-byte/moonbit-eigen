# scripts/demo.ps1 —— 一键复现演示（7 步）
#
# 类型检查 → 测试 → 三个示例；输出与日志落 demo/out/。
# 说明：docs/SCRIPTS.md 第 3 节

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

function Run($cmd) {
  Write-Host "    $ $cmd" -ForegroundColor DarkGray

  # ⚠️ PowerShell 5.1 的坑：把原生命令的 stderr 用 2>&1 接进管道会产生
  # NativeCommandError；脚本开头设了 $ErrorActionPreference = 'Stop'，
  # 于是那条 stderr 会变成**终止性错误**，脚本直接崩在"判读退出码"之前。
  # 实测：moon check 会把一条 warning 写到 stderr，正好触发这个坑。
  # 因此这里临时切回 Continue，并以 $LASTEXITCODE 作为唯一成功判据。
  $saved = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $output = Invoke-Expression $cmd 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $saved

  $output | ForEach-Object { Write-Host "    $_" }
  $output | Out-File -FilePath $logFile -Append -Encoding utf8
  if ($code -ne 0) {
    Write-Host ""
    Write-Host "演示中止：上一条命令失败（exit $code）" -ForegroundColor Red
    Write-Host "日志：$logFile"
    exit 1
  }
}

Write-Host "moonbit-eigen 演示" -ForegroundColor Green
Write-Host "仓库：$root"
Write-Host "日志：$logFile"

Step 1 "检查工具链"
$moon = Get-Command moon -ErrorAction SilentlyContinue
if (-not $moon) {
  $fallback = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'
  if (Test-Path -LiteralPath $fallback) { $moon = $fallback } else {
    Write-Host "未找到 moon。安装：" -ForegroundColor Red
    Write-Host '  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
    Write-Host '  irm https://cli.moonbitlang.com/install/powershell.ps1 | iex'
    exit 1
  }
}
Run "& '$moon' version --all"

Step 2 "获取第三方依赖（Eigen，按固定版本）"
Run "powershell -File scripts/fetch-eigen.ps1"

Step 3 "类型检查"
Run "& '$moon' check --target native"

Step 4 "运行测试"
Run "& '' test --target native selftest"
Run "& '' test --target native src"

Step 5 "运行示例：解线性方程组"
Run "& '$moon' run examples/solve --target native"

Step 6 "运行示例：一元线性回归"
Run "& '$moon' run examples/linreg --target native"

Step 7 "运行示例：与纯 MoonBit 实现对拍"
Run "& '$moon' run examples/crosscheck --target native"

Write-Host ""
Write-Host "演示完成，全部步骤成功。" -ForegroundColor Green
Write-Host "日志已保存：$logFile"
