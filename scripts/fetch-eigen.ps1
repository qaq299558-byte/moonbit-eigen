# scripts/fetch-eigen.ps1 —— 按固定版本获取 Eigen（Windows）
#
# 为什么用脚本而不是直接入库？
#   · Eigen 是 header-only 的目录树（数百个文件），入库会让仓库体积与审查负担陡增；
#   · 官方 agent skill 建议"钉住上游版本 + 可重复脚本"（pinned revision + repeatable script）；
#   · 版本固定后，CI 与本地拿到的是同一份代码。
#
# 为什么有多个候选源？
#   实测本机到 gitlab.com / github.com 的连接**不稳定**（会出现传输中途超时）。
#   因此这里按顺序尝试多个镜像，每个源都带重试。Eigen 是 header-only，
#   各镜像内容一致，换源不影响正确性。
#
# 用法：
#   powershell -File scripts/fetch-eigen.ps1
#   powershell -File scripts/fetch-eigen.ps1 -Ref 3.4.0
#   powershell -File scripts/fetch-eigen.ps1 -Retries 5
#
# 依赖：git

param(
  # 固定版本：不要用 master。升级时改这里并记入 docs/DECISIONS.md。
  [string]$Ref = "3.4.0",
  [string]$Destination = "src/third_party/eigen",
  # 每个源的重试次数
  [int]$Retries = 3
)

$ErrorActionPreference = "Stop"

# 路径按"脚本所在目录的上一级"解析，避免受调用方 pwd 影响。
$repoRoot = Split-Path -Parent $PSScriptRoot
$target = Join-Path $repoRoot $Destination
$targetFull = [System.IO.Path]::GetFullPath($target)

if (Test-Path -LiteralPath (Join-Path (Join-Path $target "Eigen") "Dense")) {
  Write-Host "Eigen 已存在于 $target，跳过下载。"
  exit 0
}

# 候选源，按顺序尝试。第一个是官方仓库。
$sources = @(
  @{ Name = "GitLab 官方"; Url = "https://gitlab.com/libeigen/eigen.git" },
  @{ Name = "GitHub 镜像"; Url = "https://github.com/eigenteam/eigen-git-mirror.git" },
  @{ Name = "Gitee 镜像";  Url = "https://gitee.com/mirrors/eigen.git" }
)

Write-Host "正在获取 Eigen $Ref → $target"
Write-Host ""

$parent = Split-Path -Parent $target
New-Item -ItemType Directory -Force -Path $parent | Out-Null

$succeeded = $false

foreach ($src in $sources) {
  for ($attempt = 1; $attempt -le $Retries; $attempt++) {
    Write-Host "  [尝试] $($src.Name)  第 $attempt/$Retries 次"

    # 每次尝试前清理半成品，避免"目录存在但不是完整仓库"导致下次误判成功
    if (Test-Path -LiteralPath $targetFull) {
      Remove-Item -LiteralPath $targetFull -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --depth 1 + 指定 tag：只取所需版本，减少传输量与超时概率
    #
    # ⚠️ 兼容性要点（PowerShell 5.1）：
    #   1) 这里临时把 ErrorActionPreference 调回 Continue —— 5.1 下把原生命令的
    #      stderr 用 2>&1 接进管道时，会产生 NativeCommandError，
    #      若此时是 Stop 会直接抛出终止性错误，脚本就走不到"重试下一个源"的逻辑。
    #   2) git 失败时不用异常判断，改用 $LASTEXITCODE。
    $savedEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git clone --depth 1 --branch $Ref $src.Url $targetFull 2>&1 |
      ForEach-Object { "      $_" }
    $cloneExit = $LASTEXITCODE
    $ErrorActionPreference = $savedEap

    if ($cloneExit -ne 0) {
      Write-Host "      git 退出码 $cloneExit" -ForegroundColor DarkGray
    }

    if (Test-Path -LiteralPath (Join-Path (Join-Path $target "Eigen") "Dense")) {
      Write-Host "  [成功] $($src.Name)"
      $succeeded = $true
      break
    }

    Write-Host "      （未成功）" -ForegroundColor DarkGray
    # 递增等待：网络抖动时给对端一点恢复时间
    Start-Sleep -Seconds (3 * $attempt)
  }
  if ($succeeded) { break }
}

if (-not $succeeded) {
  Write-Host ""
  Write-Host "全部候选源都失败了。可选做法：" -ForegroundColor Red
  Write-Host "  1) 检查网络： Test-NetConnection gitlab.com -Port 443"
  Write-Host "  2) 若开着代理，让 git 也走代理："
  Write-Host "       git config --global http.proxy http://127.0.0.1:7890"
  Write-Host "       git config --global https.proxy http://127.0.0.1:7890"
  Write-Host "  3) 放宽超时后重试："
  Write-Host "       git config --global http.lowSpeedLimit 0"
  Write-Host "       git config --global http.lowSpeedTime 999999"
  Write-Host "  4) 手动下载 Eigen $Ref 的 release 包，解压后把 Eigen 目录放到："
  Write-Host "       $target\Eigen"
  exit 1
}

Write-Host ""
Write-Host "完成。Eigen $Ref 已就位：$target"
