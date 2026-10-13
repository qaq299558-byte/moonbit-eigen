# scripts/demo.ps1 —— 一键复现演示（Windows）
#
# 官方验收要求"可复现的演示说明"。这个脚本就是那句话的可执行版本：
# 在一个干净的 clone 里运行它，应当得到完整、可核对的结果。
#
# 用法：
#   powershell -File scripts/demo.ps1
#
# 设计要点：
#   · 每一步都打印它在做什么（评审要看的是过程，不只是结论）
#   · 任何一步失败立即停止并给出可操作的提示
#   · 输出会同时写到 demo/out/ 便于附在提交材料里

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
  $output = Invoke-Expression $cmd 2>&1
  $output | ForEach-Object { Write-Host "    $_" }
  $output | Out-File -FilePath $logFile -Append -Encoding utf8
  if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "演示中止：上一条命令失败（exit $LASTEXITCODE）" -ForegroundColor Red
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
Run "& '$moon' test --target native"

Step 5 "运行示例：解线性方程组"
Run "& '$moon' run examples/solve --target native"

Step 6 "运行示例：一元线性回归"
Run "& '$moon' run examples/linreg --target native"

Step 7 "运行示例：与纯 MoonBit 实现对拍"
Run "& '$moon' run examples/crosscheck --target native"

Write-Host ""
Write-Host "演示完成，全部步骤成功。" -ForegroundColor Green
Write-Host "日志已保存：$logFile"
