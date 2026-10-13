# scripts/fetch-eigen.ps1 —— 按固定版本获取 Eigen（Windows）
#
# ── 为什么有两条完全不同的下载路径？────────────────────────────────────────
#
# 实测（中国大陆网络）：
#   · gitlab.com（Eigen 官方仓库所在）**连不上**：Connection reset / 21 秒超时
#   · github.com **连得上**（git 能建连，只是那边的镜像没有我们要的 ref）
#   · gitee.com 上的 "mirrors/eigen" **是另一个项目**（Artsy 的 iOS 应用，
#     不是 C++ 的 Eigen），不能用
#
# 所以设两条路径：
#   路径 A —— git clone GitLab 官方的 tag（CI 与非受限网络下最快，且是官方源）
#   路径 B —— 从 GitHub 下载「指定 commit 的源码归档 zip」。走普通 HTTPS，
#             不依赖 git 的联网协议；按 commit 锁定等价于钉死内容，比按 tag 更严格。
#
# 两条路径成功后都会做三件事：
#   1. 校验 Eigen/Dense 存在
#   2. **读出真实版本号并打印**（不假设，实测 Macros.h）
#   3. 写 SOURCE.txt 记录来源、锁定方式、实际版本 —— 可复现性的凭证
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\fetch-eigen.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\fetch-eigen.ps1 -Version 3.4.0
#
# 依赖：PowerShell 5.1+。路径 B 只用 Invoke-WebRequest + Expand-Archive，
#       不需要 git，也不需要 tar。

param(
  # 路径 A 使用的 GitLab tag
  [string]$Version = "3.4.0",

  # 路径 B 使用的 GitHub 镜像与 commit。
  # libigl/eigen 自述是 "mirror of the latest stable version of Eigen"，
  # 它**没有 tag**，所以按 commit 锁定。下面是 2026-10-13 的 master 顶端。
  [string]$GitHubRepo = "libigl/eigen",
  [string]$GitHubSha  = "1f05f51517ec4fd91eed711e0f89e97a7c028c0e",

  [string]$Destination = "src/third_party/eigen",
  [int]$Retries = 2
)

$ErrorActionPreference = 'Stop'

# 路径按"脚本所在目录的上一级"解析，避免受调用方 pwd 影响
$repoRoot   = Split-Path -Parent $PSScriptRoot
$target     = Join-Path $repoRoot $Destination
$targetFull = [System.IO.Path]::GetFullPath($target)
$densePath  = Join-Path (Join-Path $targetFull 'Eigen') 'Dense'
$macrosPath = Join-Path $targetFull 'Eigen\src\Core\util\Macros.h'
$zipUrl     = "https://github.com/$GitHubRepo/archive/$GitHubSha.zip"

# ── 辅助函数 ────────────────────────────────────────────────────────────────

function Test-EigenReady { return (Test-Path -LiteralPath $densePath) }

function Remove-Partial {
  if (Test-Path -LiteralPath $targetFull) {
    Remove-Item -LiteralPath $targetFull -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# 读出真实版本号（不假设）
function Show-EigenVersion {
  if (-not (Test-Path -LiteralPath $macrosPath)) { return '未知（找不到 Macros.h）' }
  $txt = Get-Content -LiteralPath $macrosPath -Raw
  $w = [regex]::Match($txt, '#define\s+EIGEN_WORLD_VERSION\s+(\d+)')
  $m = [regex]::Match($txt, '#define\s+EIGEN_MAJOR_VERSION\s+(\d+)')
  $n = [regex]::Match($txt, '#define\s+EIGEN_MINOR_VERSION\s+(\d+)')
  if ($w.Success -and $m.Success -and $n.Success) {
    return "$($w.Groups[1].Value).$($m.Groups[1].Value).$($n.Groups[1].Value)"
  }
  return '未知（宏解析失败）'
}

# 成功后统一收尾：校验 + 打印版本 + 写 SOURCE.txt
function Complete-Fetch($sourceDesc) {
  if (-not (Test-EigenReady)) { return $false }

  $ver = Show-EigenVersion
  Write-Host ""
  Write-Host "  Eigen/Dense 已就位"
  Write-Host "  实测版本号 : $ver"
  Write-Host "  来源       : $sourceDesc"

  # 若走的是路径 A（git clone），顺手记录 commit
  $sha = ''
  if (Test-Path -LiteralPath (Join-Path $targetFull '.git')) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $sha = (& git -C $targetFull rev-parse HEAD 2>$null)
    $ErrorActionPreference = $saved
  }

  $note = @(
    "source      = $sourceDesc",
    "fetch_date  = $(Get-Date -Format 'yyyy-MM-dd')",
    "eigen_ver   = $ver",
    "commit_sha  = $sha",
    "",
    "获取方式见 scripts/fetch-eigen.ps1：",
    "  路径 A: git clone GitLab 官方 tag",
    "  路径 B: GitHub 指定 commit 的源码归档 zip",
    "本目录不入库（见 .gitignore）；依赖版本由本文件记录。"
  ) -join "`r`n"
  [System.IO.File]::WriteAllText((Join-Path $targetFull 'SOURCE.txt'), $note,
                                 (New-Object System.Text.UTF8Encoding($false)))
  return $true
}

# ── 入口 ────────────────────────────────────────────────────────────────────

if (Test-EigenReady) {
  Write-Host "Eigen 已存在于 $target"
  Write-Host "  实测版本号：$(Show-EigenVersion)"
  exit 0
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetFull) | Out-Null

Write-Host "正在获取 Eigen（目标：$targetFull）"
Write-Host "  期望版本    : $Version"
Write-Host "  GitHub 锁定 : $GitHubRepo @ $($GitHubSha.Substring(0,12))..."
Write-Host ""

$ok = $false

# ── 路径 A：git clone GitLab 官方 tag ───────────────────────────────────────
Write-Host "[路径 A] git clone GitLab 官方 tag $Version"
for ($attempt = 1; $attempt -le $Retries -and -not $ok; $attempt++) {
  Write-Host "  第 $attempt/$Retries 次"
  Remove-Partial
  # PowerShell 5.1：把原生命令的 stderr 接管道会产生 NativeCommandError，
  # 若此时是 Stop 会抛终止性错误，导致后面的重试逻辑走不到。
  $saved = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & git clone --depth 1 --branch $Version https://gitlab.com/libeigen/eigen.git $targetFull 2>&1 |
    ForEach-Object { "      $_" }
  $cloneExit = $LASTEXITCODE
  $ErrorActionPreference = $saved
  if ($cloneExit -ne 0) { Write-Host "      git 退出码 $cloneExit" }
  if (Test-EigenReady) { $ok = $true }
  elseif ($attempt -lt $Retries) { Start-Sleep -Seconds (3 * $attempt) }
}
if ($ok) { $ok = Complete-Fetch "GitLab 官方 tag $Version" }

# ── 路径 B：GitHub 指定 commit 的源码归档 zip ───────────────────────────────
if (-not $ok) {
  Write-Host ""
  Write-Host "[路径 B] 从 GitHub 下载指定 commit 的源码归档"
  Write-Host "  这条路径走普通 HTTPS、不需要 git 联网协议，国内网络通常更可靠。"
  Write-Host ""

  $tmpRoot = Join-Path $env:TEMP ("eigen-fetch-" + [guid]::NewGuid().ToString('N'))
  $zipFile = Join-Path $tmpRoot 'eigen.zip'
  New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

  for ($attempt = 1; $attempt -le $Retries -and -not $ok; $attempt++) {
    Write-Host "  第 $attempt/$Retries 次：$zipUrl"

    try {
      # 关进度条：Invoke-WebRequest 的进度渲染会明显拖慢下载
      $oldProgress = $ProgressPreference
      $ProgressPreference = 'SilentlyContinue'
      Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing -TimeoutSec 300
      $ProgressPreference = $oldProgress
      $mb = [math]::Round((Get-Item -LiteralPath $zipFile).Length / 1MB, 1)
      Write-Host "      下载完成（$mb MB）"
    } catch {
      $ProgressPreference = 'Continue'
      Write-Host "      下载失败：$($_.Exception.Message)"
      if ($attempt -lt $Retries) { Start-Sleep -Seconds (3 * $attempt) }
      continue
    }

    try {
      $extractDir = Join-Path $tmpRoot 'extract'
      Expand-Archive -LiteralPath $zipFile -DestinationPath $extractDir -Force
      # 归档里只有一个顶层目录（形如 eigen-<sha>）
      $inner = Get-ChildItem -LiteralPath $extractDir -Directory | Select-Object -First 1
      if (-not $inner) { throw '解压后没有找到顶层目录' }

      Remove-Partial
      Move-Item -LiteralPath $inner.FullName -Destination $targetFull
      if (Test-EigenReady) { $ok = $true }
      else { Write-Host "      解压完成但没有 Eigen/Dense，可能不是预期的仓库" }
    } catch {
      Write-Host "      解压失败：$($_.Exception.Message)"
      if ($attempt -lt $Retries) { Start-Sleep -Seconds (3 * $attempt) }
    }
  }

  Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
  if ($ok) { $ok = Complete-Fetch "GitHub $GitHubRepo @ $GitHubSha (zip)" }
}

# ── 结果 ────────────────────────────────────────────────────────────────────

Write-Host ""
if ($ok) {
  Write-Host "完成。Eigen 已就位：$target" -ForegroundColor Green
  Write-Host "下一步：  moon test --target native"
  exit 0
}

Write-Host "两条路径都失败了。可选做法：" -ForegroundColor Red
Write-Host "  1) 检查网络："
Write-Host "       Test-NetConnection github.com -Port 443"
Write-Host "       Test-NetConnection gitlab.com -Port 443"
Write-Host "  2) 若开着代理，让命令行也走代理（端口按实际改）："
Write-Host "       `$env:HTTP_PROXY  = 'http://127.0.0.1:7890'"
Write-Host "       `$env:HTTPS_PROXY = 'http://127.0.0.1:7890'"
Write-Host "  3) 用浏览器手动下载后解压（浏览器常配了代理，命令行没有）："
Write-Host "       $zipUrl"
Write-Host "     解压后把里面的 Eigen 目录放到："
Write-Host "       $targetFull\Eigen"
exit 1
