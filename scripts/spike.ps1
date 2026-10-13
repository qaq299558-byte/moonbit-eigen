# scripts/spike.ps1 —— 一键技术穿刺（Windows）
#
# 目的：把 docs/ROADMAP.md 第 1 周的检查项压缩成一条命令，并对熔断点给出判定结论。
#
# 步骤顺序是**刻意设计**的：
#   1. 工具链
#   2. moon check（纯类型检查，不需要 C 编译器）
#   3. **selftest 自检包** ← 这一步给出 "Plan A 是否成立" 的结论，
#                            而且**不需要 Eigen**（本机网络不稳，先拿到最关键的结论）
#   4. 获取 Eigen
#   5. 完整测试（含 Eigen）
#   6. 结论
#
# 用法：
#   powershell -File scripts/spike.ps1

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
Section "Step 1/6 工具链"

$moon = Get-Command moon -ErrorAction SilentlyContinue
if (-not $moon) {
  $fallback = Join-Path $env:USERPROFILE '.moon\bin\moon.exe'
  if (Test-Path -LiteralPath $fallback) {
    $moon = $fallback
    Warn "moon 不在 PATH，但找到 $fallback（本次用它；建议把 .moon\bin 加进 PATH）"
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

$hasCxx = $false
foreach ($c in 'cl', 'clang-cl') {
  $p = Get-Command $c -ErrorAction SilentlyContinue
  if ($p) { Ok "$c -> $($p.Source)"; $hasCxx = $true }
}
if (-not $hasCxx) {
  Fail "未找到 cl.exe 或 clang-cl.exe"
  Write-Host "         Windows 上 native 后端只接受 MSVC 兼容工具链（MinGW 被官方排除）。" -ForegroundColor DarkGray
  Write-Host "         本机装了 VS Build Tools 但缺 C++ 工作负载时，加装它即可：" -ForegroundColor DarkGray
  Write-Host '           & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" modify `'
  Write-Host '               --installPath "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools" `'
  Write-Host '               --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet'
  Write-Host "         或者改用 LLVM（然后在 src/moon.pkg 里加回 cc / stub-cc）：" -ForegroundColor DarkGray
  Write-Host "           winget install LLVM.LLVM" -ForegroundColor DarkGray
  $verdict += "Step 1 失败：未安装 MSVC 兼容 C++ 工具链"
}

if ($verdict.Count -gt 0) {
  Write-Host ""
  Write-Host "穿刺中止。先解决上面标 [FAIL] 的问题。" -ForegroundColor Red
  exit 1
}

# ── Step 2：MoonBit 类型检查（不需要 C 编译器）────────────────────────────────
Section "Step 2/6 moon check（纯类型检查，覆盖 API 层 + 测试 + 示例）"
& $moon check --target native
if ($LASTEXITCODE -ne 0) {
  Fail "moon check 未通过"
  $verdict += "Step 2 未通过：MoonBit 侧有类型错误，先修它们"
} else {
  Ok "MoonBit 侧类型检查通过"
}

# ── Step 3：FFI 机制自检（★ 关键：不需要 Eigen）──────────────────────────────
Section "Step 3/6 selftest：FFI 机制判定（Plan A/B 的结论在这里出来）"
Write-Host "  这个包零第三方依赖，只验证 native FFI 机制本身：" -ForegroundColor DarkGray
Write-Host "  extern C 导出 / moonbit_make_external_object + finalizer / #borrow /" -ForegroundColor DarkGray
Write-Host "  错误哨兵约定 / moonbit_make_bytes + @utf8 的编码往返。" -ForegroundColor DarkGray
Write-Host ""
& $moon test --target native selftest
if ($LASTEXITCODE -ne 0) {
  Fail "selftest 未通过 —— 这直接决定 Plan A 是否成立"
  Write-Host "    先试强制 C 后端（新 native 后端可能不支持 stub）：" -ForegroundColor DarkGray
  Write-Host "      `$env:MOONBIT_NEW_NATIVE = '0'; moon test --target native selftest" -ForegroundColor DarkGray
  Write-Host "    若报错是「编译 .cpp 失败」或「找不到 mb_smoke_* 符号」，说明 .cpp 不能作 native-stub，" -ForegroundColor DarkGray
  Write-Host "    需要执行 Plan B（见 docs/PLAN_B.md）。" -ForegroundColor DarkGray
  $verdict += "Step 3 失败：Plan A（.cpp 作 native-stub）可能不成立 → 需判定是否切 Plan B"
} else {
  Ok "FFI 机制全部可用 —— Plan A 成立 ✅"
}

# ── Step 4：Eigen ─────────────────────────────────────────────────────────────
Section "Step 4/6 获取 Eigen（按固定版本，多镜像重试）"
if (Test-Path -LiteralPath (Join-Path $root 'src\third_party\eigen\Eigen\Dense')) {
  Ok "Eigen 已就位"
} else {
  & (Join-Path $PSScriptRoot 'fetch-eigen.ps1')
  if (Test-Path -LiteralPath (Join-Path $root 'src\third_party\eigen\Eigen\Dense')) {
    Ok "Eigen 获取成功"
  } else {
    Fail "Eigen 获取失败（网络问题，见脚本输出的备选做法）"
    $verdict += "Step 4 失败：Eigen 未就位 —— 完整测试无法进行，但 Step 3 的结论仍然有效"
  }
}

# ── Step 5：完整测试（含 Eigen）───────────────────────────────────────────────
Section "Step 5/6 moon test --target native（完整测试，含 Eigen 绑定）"
if (Test-Path -LiteralPath (Join-Path $root 'src\third_party\eigen\Eigen\Dense')) {
  & $moon test --target native
  if ($LASTEXITCODE -ne 0) {
    Fail "完整测试未通过"
    $verdict += "Step 5 失败：Eigen 绑定的编译或测试有问题"
  } else {
    Ok "全部测试通过 —— L0 路径打通 ✅"
  }
} else {
  Warn "跳过：Eigen 未就位"
}

# ── Step 6：结论 ──────────────────────────────────────────────────────────────
Section "穿刺结论"
if ($verdict.Count -eq 0) {
  Write-Host "  全部通过。截至 $(Get-Date -Format 'yyyy-MM-dd')：" -ForegroundColor Green
  Write-Host "    · Plan A 成立（.cpp 可作为 native-stub）" -ForegroundColor Green
  Write-Host "    · MoonBit 侧与 C++ 侧都已验证" -ForegroundColor Green
  Write-Host "    · README 的'接口契约'措辞可以改成'已验证可用'" -ForegroundColor Green
  Write-Host "    · 下一步：按 docs/ROADMAP.md 的 W2 推进" -ForegroundColor Green
} else {
  Write-Host "  结论：" -ForegroundColor Yellow
  foreach ($v in $verdict) { Write-Host "    · $v" -ForegroundColor Yellow }
  Write-Host "  请把结论回填到 docs/PITFALLS.md 第 8 节，并提交一次 commit。" -ForegroundColor Yellow
}
