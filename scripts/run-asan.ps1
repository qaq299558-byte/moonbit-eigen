# scripts/run-asan.ps1 —— 用 AddressSanitizer 跑测试（Windows / MSVC）
#
# ── 为什么需要它 ────────────────────────────────────────────────────────────
# 跨语言边界的所有权类 bug（悬垂引用、双重释放、越界写）大多"运行时才炸、
# 且不炸在出错点"。官方 agent skill 把 ASan 列为第 1 周就该接上的东西。
#
# ── 实测出来的完整配方（2026-10-13）─────────────────────────────────────────
# 1. 往 src/moon.pkg 的 stub-cc-flags 里加 /fsanitize=address
#    → 插桩后的 .obj 会自动带上 clang_rt.asan 的 default-lib 指令，
#      因此**不需要**往 cc-link-flags 里加东西
#      （加了反而会让 link.exe 报 LNK4044「无法识别的选项」）。
# 2. **必须把 ASan 运行时 DLL 所在目录放进 PATH**，否则测试进程直接
#    以 0xc0000135（STATUS_DLL_NOT_FOUND）退出 —— 看起来像测试失败，
#    实际是找不到 clang_rt.asan_dynamic-x86_64.dll。
#    这个目录就是 cl.exe 自己的目录（vcvars 会把它加进 PATH）。
# 3. 可选：cc-link-flags 加 /DEBUG 可让 ASan 报告带行列号；
#    不加会有一条 LNK4302 警告，但功能正常。
#
# ── 防"假绿" ────────────────────────────────────────────────────────────────
# ASan 最危险的失败模式是**没生效却报告成功**。本脚本因此有两道断言：
#   · 注入后必须真的改动了 moon.pkg（找不到目标字段就直接报错退出）
#   · 跑完必须确认测试 exe 里引用了 clang_rt.asan，否则判定为假绿并报错
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\run-asan.ps1
#
# 说明：只插桩 C++ 胶水层（src 的 native-stub）。MoonBit 生成的 C 代码
# 要插桩需改 cc-flags，而 cc-flags 会**替换** moon 的全部默认编译选项，
# 风险大收益小 —— 本项目真正的风险代码是 FFI 边界上的那层 C++ 胶水。

param(
  # 测试哪个包；默认 src（含 Eigen 绑定）
  [string]$Package = "src"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$pkgPath = Join-Path $repoRoot 'src\moon.pkg'
$backup  = Join-Path $repoRoot '.git\moon.pkg.asan-backup'
$marker  = '/fsanitize=address'
$dirty   = $false

function Fail($msg) {
  Write-Host ""
  Write-Host "失败：$msg" -ForegroundColor Red
  exit 1
}

# ── 1. 找 moon ──────────────────────────────────────────────────────────────
$moon = $null
$moonCmd = Get-Command moon -ErrorAction SilentlyContinue
if ($moonCmd) {
  $moon = $moonCmd.Source
} else {
  $fallback = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'
  if (Test-Path -LiteralPath $fallback) { $moon = $fallback }
}
if (-not $moon) { Fail "未找到 moon。请先安装 MoonBit 工具链。" }

# ── 2. 找 MSVC 与 ASan 运行时目录 ───────────────────────────────────────────
$asanDir = $null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $vswhere) {
  $installs = & $vswhere -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath 2>$null
  foreach ($ip in $installs) {
    $msvcRoot = Join-Path $ip 'VC\Tools\MSVC'
    if (-not (Test-Path -LiteralPath $msvcRoot)) { continue }
    $latest = Get-ChildItem -LiteralPath $msvcRoot -Directory |
      Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { continue }
    $cand = Join-Path $latest.FullName 'bin\Hostx64\x64'
    if (Test-Path -LiteralPath (Join-Path $cand 'clang_rt.asan_dynamic-x86_64.dll')) {
      $asanDir = $cand
      break
    }
  }
}
if (-not $asanDir) {
  Fail "找不到 clang_rt.asan_dynamic-x86_64.dll。`n" +
       "        它随 VS 的 C++ 工作负载一起安装；本机若用其它工具链，" +
       "请把包含该 DLL 的目录手动加进 PATH。"
}

Write-Host "ASan 测试（Windows / MSVC）"
Write-Host "  moon      : $moon"
Write-Host "  ASan 运行时: $asanDir"
Write-Host "  目标包    : $Package"
Write-Host ""

# ── 3. 注入编译选项（并把 PATH 准备好）──────────────────────────────────────
if (-not (Test-Path -LiteralPath $pkgPath)) { Fail "找不到 $pkgPath" }
Copy-Item -LiteralPath $pkgPath -Destination $backup -Force

try {
  $text = [System.IO.File]::ReadAllText($pkgPath, [System.Text.UTF8Encoding]::new($false))
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }

  if ($text.Contains($marker)) {
    Write-Host "  提示：moon.pkg 里已经有 $marker，跳过注入。" -ForegroundColor DarkGray
  } else {
    $m = [regex]::Match($text, '"stub-cc-flags"\s*:\s*"([^"]*)"')
    if (-not $m.Success) {
      # ★ 这一条就是防"假绿"：早期版本的脚本用正则替换一个不存在的字段，
      #   替换静默失败，脚本照样报告"sanitizer 运行结束（无输出即无问题）"。
      Fail "在 src/moon.pkg 里找不到 `"stub-cc-flags`" 字段，无法注入 $marker。`n" +
           "        请确认 moon.pkg 的结构，或手动往 stub-cc-flags 里加 $marker。"
    }
    $old = $m.Value
    $new = '"stub-cc-flags": "' + $m.Groups[1].Value.TrimEnd() + " $marker" + '"'
    $text = $text.Replace($old, $new)
    [System.IO.File]::WriteAllText($pkgPath, $text, [System.Text.UTF8Encoding]::new($false))
    $dirty = $true
    Write-Host "  已注入：$new"
  }

  # ASan 运行时 DLL 必须在 PATH 上，否则测试进程以 0xc0000135 退出
  $env:PATH = "$asanDir;$env:PATH"

  Write-Host ""
  Write-Host "=== 运行测试（ASan 已启用）==="
  $saved = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $moon test --target native $Package
  $testExit = $LASTEXITCODE
  $ErrorActionPreference = $saved

  if ($testExit -ne 0) {
    Write-Host ""
    Write-Host "测试未通过（退出码 $testExit）。" -ForegroundColor Red
    Write-Host "若退出码是 0xc0000135，那是找不到 ASan 运行时 DLL，不是测试失败。"
    exit 1
  }

  # ── 4. 断言 ASan 真的生效（防假绿）────────────────────────────────────────
  $exes = Get-ChildItem -LiteralPath (Join-Path $repoRoot '_build') -Recurse `
            -Filter '*.exe' -File -ErrorAction SilentlyContinue |
          Where-Object { $_.Name -like "*$Package*test*" }
  $verified = $false
  foreach ($e in $exes) {
    $txt = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($e.FullName))
    if ($txt.Contains('clang_rt.asan') -or $txt.Contains('__asan')) {
      $verified = $true
      Write-Host ""
      Write-Host "  已确认 ASan 生效：$($e.Name) 引用了 ASan 运行时"
      break
    }
  }
  if (-not $verified) {
    Write-Host ""
    Fail "测试虽然通过了，但产物里没有 ASan 痕迹 —— 这是**假绿**。`n" +
         "        说明 $marker 没有真正生效，本次运行不能作为内存安全证据。"
  }

  Write-Host ""
  Write-Host "ASan 测试通过（$Package）。" -ForegroundColor Green
  Write-Host "注意：只插桩了 C++ 胶水层；MoonBit 生成的 C 代码未插桩（原因见脚本头部注释）。"
  exit 0
} finally {
  if ($dirty -and (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $backup -Destination $pkgPath -Force
    Write-Host "  （src/moon.pkg 已还原）"
  }
  Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
}
