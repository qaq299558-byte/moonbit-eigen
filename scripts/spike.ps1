# scripts/spike.ps1 —— 一键技术穿刺（Windows）
#
# 目的：把 docs/ROADMAP.md 第 1 周的检查项压缩成一条命令，
#       并对熔断点直接给出判定结论。
#
# 用法：
#   pwsh -File scripts/spike.ps1
#
# 判定规则：
#   Step 1-2 失败 → 工具链问题，看 README 的安装说明
#   Step 3   失败 → 先试 MOONBIT_NEW_NATIVE=0；仍失败则考虑 VS Build Tools
#   Step 4   失败 → 已定论：.cpp 不能作 native-stub，执行 Plan B（见 moon.pkg 注释）
#   Step 5   失败 → probe 未返回预期值，检查 Eigen 是否就位

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$verdict = @()

function Section($title) {
  Write-Host ""
  Write-Host "=== $title ===" -ForegroundColor Cyan
}

function Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

# ── Step 1：工具链 ────────────────────────────────────────────────────────────
Section "Step 1/5 工具链"

$moon = Get-Command moon -ErrorAction SilentlyContinue
if (-not $moon) {
  $fallback = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'
  if (Test-Path -LiteralPath $fallback) {
    $moon = $fallback
    Warn "moon 不在 PATH，但找到 $fallback（本次使用它；建议把 .moon\bin 加入 PATH）"
  }
}
if ($moon) {
  Ok "moon: $(& $moon version 2>&1 | Select-Object -First 1)"
} else {
  Fail "未找到 moon。安装方式："
  Write-Host '         Set-ExecutionPolicy RemoteSigned -Scope CurrentUser'
  Write-Host '         irm https://cli.moonbitlang.com/install/powershell.ps1 | iex'
  $verdict += "Step 1 失败：未安装 MoonBit 工具链"
}

$clangcl = Get-Command clang-cl -ErrorAction SilentlyContinue
if ($clangcl) {
  Ok "clang-cl: $($clangcl.Source)"
} else {
  $cl = Get-Command cl -ErrorAction SilentlyContinue
  if ($cl) {
    Ok "cl.exe: $($cl.Source)"
    Warn "你装的是 MSVC。moon.pkg 里默认写的是 clang-cl，需要改成 `"cl`""
  } else {
    Fail "未找到 clang-cl 或 cl.exe（Windows 上必须用 MSVC 兼容工具链，MinGW 被官方排除）"
    Write-Host '         winget install LLVM.LLVM'
    $verdict += "Step 1 失败：未安装 MSVC 兼容 C++ 工具链"
  }
}

if ($verdict.Count -gt 0) {
  Write-Host ""
  Write-Host "穿刺中止。先解决上面标 [FAIL] 的问题。" -ForegroundColor Red
  exit 1
}

# ── Step 2：Eigen ─────────────────────────────────────────────────────────────
Section "Step 2/5 获取 Eigen"
if (Test-Path -LiteralPath (Join-Path $root 'src\third_party\eigen\Eigen\Dense')) {
  Ok "Eigen 已就位"
} else {
  & (Join-Path $PSScriptRoot 'fetch-eigen.ps1')
  if (Test-Path -LiteralPath (Join-Path $root 'src\third_party\eigen\Eigen\Dense')) {
    Ok "Eigen 获取成功"
  } else {
    Fail "Eigen 获取失败"
    $verdict += "Step 2 失败：Eigen 未就位"
  }
}

# ── Step 3：MoonBit 类型检查（不需要 C 编译器）────────────────────────────────
Section "Step 3/5 moon check（纯类型检查，验证 MoonBit 语法）"
Write-Host "  注意：这一步会暴露 src/*.mbt 里那些未经编译验证的 API 名。" -ForegroundColor DarkGray
Write-Host "        待验证清单见 docs/PITFALLS.md 第 8 节。" -ForegroundColor DarkGray
& $moon check --target native
if ($LASTEXITCODE -ne 0) {
  Warn "moon check 未通过 —— 这通常意味着需要按 PITFALLS §8 修正 API 名，而不是熔断"
  $verdict += "Step 3 未通过：需要按 docs/PITFALLS.md §8 修正 MoonBit API 名"
}

# ── Step 4：native 构建 + 链接（熔断点 2）─────────────────────────────────────
Section "Step 4/5 moon test --target native（熔断点：.cpp 能否作 native-stub）"
& $moon test --target native
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Warn "若报错是'找不到 mb_eigen_* 符号'或编译 .cpp 失败，说明 Plan A 不可行。"
  Warn "先试：`$env:MOONBIT_NEW_NATIVE = '0' 后重跑。"
  Warn "仍失败则执行 Plan B：预编译静态库 + cc-link-flags（见 src/moon.pkg 注释）。"
  $verdict += "Step 4 失败：Plan A（.cpp 作 native-stub）可能不可行 → 需判定是否切 Plan B"
} else {
  Ok "native 构建与测试通过 —— Plan A 成立"
}

# ── Step 5：probe 交叉验证 ────────────────────────────────────────────────────
Section "Step 5/5 构建期自检"
Write-Host "  mb_eigen_shim_probe 预期 >= 17000（C++17 + Eigen 3.x）"
Write-Host "  该断言已在 src/eigen_test.mbt 的 'shim probe' 测试中，Step 4 通过即代表它通过。"
Ok "见 Step 4 结果"

# ── 结论 ──────────────────────────────────────────────────────────────────────
Section "穿刺结论"
if ($verdict.Count -eq 0) {
  Write-Host "  全部通过。截至 $(Get-Date -Format 'yyyy-MM-dd')：" -ForegroundColor Green
  Write-Host "    · Plan A 成立（.cpp 可作为 native-stub）" -ForegroundColor Green
  Write-Host "    · 可以把 README 的'接口契约'措辞改为'已验证可用'" -ForegroundColor Green
  Write-Host "    · 下一步：按 docs/ROADMAP.md W2 推进运算功能" -ForegroundColor Green
} else {
  Write-Host "  结论：" -ForegroundColor Yellow
  foreach ($v in $verdict) { Write-Host "    · $v" -ForegroundColor Yellow }
  Write-Host "  请把这些结论回填到 docs/PITFALLS.md 第 8 节，并提交一次 commit。" -ForegroundColor Yellow
}
