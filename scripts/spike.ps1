# scripts/spike.ps1 —— 兼容旧名称：环境自检已并入 demo.ps1
#
# 为什么保留这个文件：
#   它原本是一个 6 步的环境自检脚本（工具链 → 类型检查 → FFI 自检 →
#   取 Eigen → 完整测试 → 结论）。后来发现它与 demo.ps1 有约 80% 重复，
#   于是独有的两件事（vswhere 检测 MSVC、"先自检再取依赖"的顺序）
#   全部并入 demo.ps1。
#
#   但早期的文档、docs/DECISIONS.md 与提交记录里都引用了这个文件名，
#   所以这里保留一个薄壳：按旧文档操作的人仍然能一条命令跑通完整自检。
#
# 说明：docs/SCRIPTS.md 第 2 节

# 用子进程跑 demo.ps1：demo 内部用 exit 结束，
# 若直接在当前会话里调用，会把调用者的 shell 一起关掉。
$demo = Join-Path $PSScriptRoot 'demo.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $demo
exit $LASTEXITCODE