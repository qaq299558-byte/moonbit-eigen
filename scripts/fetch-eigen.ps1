# scripts/fetch-eigen.ps1 —— 按固定版本获取 Eigen（Windows）
#
# ── 三条路径的由来（全部来自实测，不是推测）────────────────────────────────
#
# 实测网络（中国大陆，无代理）：
#   · gitlab.com（Eigen 官方仓库）      —— 连不上：Connection reset / 30 秒超时
#   · github.com 经 git 协议            —— **可以连**（能读到 ref 列表）
#   · github.com 经 Invoke-WebRequest   —— 连不上（archive/ 会 302 到
#                                          codeload.github.com，那个域名不通）
#   · gitee.com/mirrors/eigen          —— **是另一个项目**（Artsy 的 iOS 应用），
#                                          不是 C++ 的 Eigen，不能用
#
# 因此路径按"实测成功率"排序：
#   路径 A —— git clone GitLab 官方 tag（官方源；CI 与非受限网络走这条）
#   路径 B —— git clone GitHub 镜像的 master（★ 受限网络下最可能成功，
#              因为 git 协议到 github.com 已被实测证明可达）
#   路径 C —— GitHub 指定 commit 的源码归档 zip（普通 HTTPS，
#              适合"git 被封但 HTTPS 通"的网络；已强制 TLS 1.2）
#
# 任一条成功即可。成功后都会：
#   1. 校验 Eigen/Dense 存在（并确认内容确实是 Eigen 的 Dense 头）
#   2. **读出真实版本号并打印**（解析 Macros.h，不假设）
#   3. 写 SOURCE.txt 记录来源、锁定方式、实际 commit 与版本
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\fetch-eigen.ps1
#
# 依赖：PowerShell 5.1+。路径 C 只用 Invoke-WebRequest + Expand-Archive。

param(
  # 路径 A 使用的 GitLab tag
  [string]$Version = "3.4.0",

  # 路径 B 使用的 GitHub 镜像（已验证 Eigen/Dense 存在）与分支
  [string]$GitHubRepo   = "libigl/eigen",
  [string]$GitHubBranch = "master",

  # 路径 C 锁定的 commit（2026-10-13 时 libigl/eigen 的 master 顶端）
  [string]$GitHubSha = "1f05f51517ec4fd91eed711e0f89e97a7c028c0e",

  [string]$Destination = "src/third_party/eigen",
  [int]$Retries = 2
)

$ErrorActionPreference = 'Stop'

# PowerShell 5.1 默认可能只启用 TLS 1.0/1.1，而 GitHub 要求 TLS 1.2+。
# 这是 5.1 访问 GitHub 的经典坑，必须显式打开（对 git 无影响，只影响 .NET HTTP）。
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

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

# 运行 git 并把输出转发出来；临时把 ErrorActionPreference 调回 Continue，
# 因为 5.1 下把原生命令 stderr 接管道会抛 NativeCommandError。
function Invoke-Git([string[]]$GitArgs) {
  $saved = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  # 用 Write-Host 而不是直接输出字符串：PowerShell 函数会把所有管道输出
  # 都当作返回值，直接输出会让 git 的日志混进 $code 里（实测踩过）。
  & git @GitArgs 2>&1 | ForEach-Object { Write-Host "      $_" }
  $code = $LASTEXITCODE
  $ErrorActionPreference = $saved
  return $code
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
    "  路径 A: git clone GitLab 官方 tag（官方源）",
    "  路径 B: git clone GitHub 镜像 master",
    "  路径 C: GitHub 指定 commit 的源码归档 zip",
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
Write-Host "  GitHub 镜像 : $GitHubRepo @ $GitHubBranch"
Write-Host "  锁定 commit : $($GitHubSha.Substring(0,12))..."
Write-Host ""

$ok = $false

# ── 路径 A：git clone GitLab 官方 tag ───────────────────────────────────────
Write-Host "[路径 A] git clone GitLab 官方 tag $Version"
for ($attempt = 1; $attempt -le $Retries -and -not $ok; $attempt++) {
  Write-Host "  第 $attempt/$Retries 次"
  Remove-Partial
  $code = Invoke-Git -GitArgs @('clone', '--depth', '1', '--branch', $Version,
                       'https://gitlab.com/libeigen/eigen.git', $targetFull)
  if ($code -ne 0) { Write-Host "      git 退出码 $code" }
  if (Test-EigenReady) { $ok = $true }
  elseif ($attempt -lt $Retries) { Start-Sleep -Seconds (3 * $attempt) }
}
if ($ok) { $ok = Complete-Fetch "GitLab 官方 tag $Version" }

# ── 路径 B：git clone GitHub 镜像（受限网络下最可能成功）──────────────────
if (-not $ok) {
  Write-Host ""
  Write-Host "[路径 B] git clone GitHub 镜像 $GitHubRepo（分支 $GitHubBranch）"
  Write-Host "  选它的理由：git 协议到 github.com 在实测中是可达的。"
  Write-Host ""
  for ($attempt = 1; $attempt -le $Retries -and -not $ok; $attempt++) {
    Write-Host "  第 $attempt/$Retries 次"
    Remove-Partial
    $code = Invoke-Git -GitArgs @('clone', '--depth', '1', '--branch', $GitHubBranch,
                         "https://github.com/$GitHubRepo.git", $targetFull)
    if ($code -ne 0) { Write-Host "      git 退出码 $code" }
    if (Test-EigenReady) {
      # 尽力把内容锁定到指定 commit（浅克隆不一定允许按 SHA 取，失败不影响使用）
      Write-Host "      尝试锁定到 commit $($GitHubSha.Substring(0,12))..."
      $fetchCode = Invoke-Git -GitArgs @('-C', $targetFull, 'fetch', '--depth', '1',
                                'origin', $GitHubSha)
      if ($fetchCode -eq 0) {
        $coCode = Invoke-Git -GitArgs @('-C', $targetFull, 'checkout', '--detach', 'FETCH_HEAD')
        if ($coCode -eq 0) {
          Write-Host "      已锁定到指定 commit"
        } else {
          Write-Host "      按 SHA 检出失败（不影响使用，内容为该镜像当前 master）"
        }
      } else {
        Write-Host "      该镜像不允许按 SHA 浅取（不影响使用，内容为当前 master）"
      }
      $ok = $true
    }
    elseif ($attempt -lt $Retries) { Start-Sleep -Seconds (3 * $attempt) }
  }
  if ($ok) { $ok = Complete-Fetch "GitHub $GitHubRepo @ $GitHubBranch (git clone)" }
}

# ── 路径 C：GitHub 指定 commit 的源码归档 zip（普通 HTTPS）─────────────────
if (-not $ok) {
  Write-Host ""
  Write-Host "[路径 C] 从 GitHub 下载指定 commit 的源码归档（普通 HTTPS）"
  Write-Host "  注意：archive/ 会 302 到 codeload.github.com；"
  Write-Host "        若该域名不通，这条路径会失败（此时应优先用路径 B）。"
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

Write-Host "三条路径都失败了。可选做法：" -ForegroundColor Red
Write-Host "  1) 检查网络（重点看 github.com 的 git 端口是否可达）："
Write-Host "       Test-NetConnection github.com -Port 443"
Write-Host "       git ls-remote https://github.com/libigl/eigen.git"
Write-Host "  2) 若开着代理，让命令行也走代理（端口按实际改）："
Write-Host "       `$env:HTTP_PROXY  = 'http://127.0.0.1:7890'"
Write-Host "       `$env:HTTPS_PROXY = 'http://127.0.0.1:7890'"
Write-Host "       git config --global http.proxy http://127.0.0.1:7890"
Write-Host "  3) 用浏览器手动下载后解压（浏览器常配了代理，命令行没有）："
Write-Host "       $zipUrl"
Write-Host "     解压后把里面的 Eigen 目录放到："
Write-Host "       $targetFull\Eigen"
exit 1
