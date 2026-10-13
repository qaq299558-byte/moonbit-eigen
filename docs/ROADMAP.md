# 里程碑、熔断点与降级阶梯

> 验收截止 **2026-10-31**。今天是 **2026-10-13**，剩 **18 天**，**单人**。
> 时间预算：每天有效开发 3–4 小时 → 全程约 **60 小时**。

---

## 1. 三级降级阶梯（保证 10/31 一定有东西交）

| 级别 | 内容 | 触发条件 | 完成度 |
|---|---|---|---|
| **L0 完整版** | 17 个 C 函数全支持 + MoonBit API + 单测 + 3 个示例 + CI + 全套文档 | 顺利 | 100% |
| **L1 精简版** | 只做 `zeros`/`from_array`/`to_array`/`get`/`set`/`mul`/`solve` + 单测 + 1 个示例 + 文档 | 落后 3 天以上 | ~65% |
| **L2 保底版** | **纯 C 胶水**的互操作套件：类型映射表 + 踩坑文档 + 2 个可运行示例（用自己写的 C++ 小类经 C 接口暴露）+ 模板仓库 | `.cpp` 走不通或工具链装不上 | ~50%，但仍是完整可验收的交付 |

**L2 为什么仍然满足"必要测试/可运行示例/README"三条**：
它换掉的是"被绑定的库"，不是交付形态。类型映射表与踩坑记录是本项目最有复用价值的部分，
在 L2 下依然完整保留。

---

## 2. 熔断点（不许讨价还价）

| 时间点 | 检查项 | 不通过怎么办 |
|---|---|---|
| **10/16 结束** | `moon build --target native` 跑通 Hello World | 先试 `MOONBIT_NEW_NATIVE=0`；再不行改用 VS Build Tools（而非 clang-cl） |
| **10/19 结束** | `.cpp` 作为 `native-stub` 能编译并链接（`mb_eigen_shim_probe` 返回 ≥ 17000） | **立即切 Plan B**（脚本预编译静态库 + `cc-link-flags`） |
| **10/23 结束** | 矩阵乘法在 MoonBit 侧跑通 | **立即切 L1 精简版**，砍掉示例数量与文档深度 |
| **10/27 结束** | 示例可运行 + 单测全绿 | **立即切 L2 保底版**，把剩余时间全部投入文档与验收材料 |

**为什么熔断点这么靠前**：唯一可能"全盘失败"的环节是 C++ 胶水能否进入构建，
必须最早证伪。18 天不允许在"能不能跑起来"上无限投入。

---

## 3. 周计划

### W1（10/13–10/19）工具链穿刺 + ASan 接线 —— **基本完成（10/13 当天）**

**目标：证明技术路径可行，而不是写功能。**

- [x] ~~工具链就位~~ → MoonBit `0.1.20261012`/`moonc v0.10.15` + VS Build Tools 18 / MSVC 14.51
- [x] ~~骨架代码跑通 `moon check`~~ → **0 errors**（覆盖 API 层 + FFI 声明 + 全部测试 + 3 个示例）
- [x] ~~`.cpp` 能否作 native-stub~~ → **成立（Plan A）**，`moon test --target native selftest` **7/7 通过**
      → **熔断点解除，不需要切 Plan B**
- [x] ~~补齐 `scripts/fetch-eigen.sh`~~ → 已就位（含多镜像 + 重试）
- [x] ~~按固定版本获取 Eigen~~ → ✅ `scripts/fetch-eigen.ps1`（三路径 + 版本校验写 SOURCE.txt）
- [x] ~~`mb_eigen_shim_probe`~~ → ✅ 已跑通并返回预期值，证明 C++17 + Eigen 都进来了
- [x] ~~跑通完整测试~~ → ✅ **38 个测试全绿**（src 18 + reference 13 + selftest 7）；注意必须带包名（见 PITFALLS 10.2）
- [x] ~~**把 ASan 接上**~~ → ✅ **10/13 完成**（Windows/MSVC）：18/18 在 ASan 生效下通过，产物确认引用 `clang_rt.asan`。配方见 docs/PITFALLS.md 第 12 节
      —— 官方明确建议把它作为**第 1 周交付物**而非最后一步，因为
      所有权类 bug 大多"运行时才炸、且不炸在出错点"

### W2（10/20–10/26）胶水层 + MoonBit API + 测试

- [x] ~~用真实矩阵替换 probe~~ → ✅ `mat_new` / `mat_from_array` / `mat_copy_to` 已跑通
- [x] ~~运算打通：加、减、乘、转置、数乘~~ → ✅ 已完成
- [x] ~~`solve` / `det` / `norm` / `dot` 打通，含奇异矩阵检测~~ → ✅ 已完成，奇异矩阵返回 Err 而非崩溃
- [x] ~~`eigen_wbtest.mbt` 全绿~~ → ✅ **18 个**（含错误路径测试）
- [x] ~~校验 `#borrow` 行为~~ → ✅ 生效、未崩溃（`FixedArray[Double]` 参数正常）
- [x] ~~记录实测结果到 PITFALLS 第 8 节~~ → ✅ 已逐条回填
- [x] ~~**【熔断点】** 10/23：矩阵乘法是否跑通~~ → ✅ 已跑通，熔断点解除

### W3（10/27–10/30 前半）示例 + 文档

- [x] ~~`examples/solve`~~ → ✅ 解方程组 + 错误路径演示
- [x] ~~`examples/linreg`~~ → ✅ 一元线性回归（精确复原截距 1 / 斜率 2）
- [x] ~~`examples/crosscheck`~~ → ✅ **5 组对拍**：乘法 0、解方程 2.2e-16 / 1.1e-16、行列式、奇异矩阵判定
- [x] ~~补齐 `docs/DESIGN.md`~~ → ✅ 已写（ABI 边界为什么这样切，9 节）
- [x] ~~README 补齐实测数据~~ → ✅ 全部为已验证数据（38/38、8 步演示、5 组对拍）
- [x] ~~**【熔断点】** 10/27：示例与测试是否就绪~~ → ✅ 已就绪，熔断点解除

### W4（10/30–10/31）演示与验收

- [x] ~~`scripts/demo.ps1` / `scripts/demo.sh`~~ → ✅ `demo.ps1` 8 步全过（`spike.ps1` 为兼容薄壳）；日志落在 `demo/out/`
- [ ] 终端录屏 / GIF（单人项目缺"团队故事"，靠演示直观度补）
- [ ] **在干净目录**重新 clone → 按 README 步骤复现 —— ⚠️ **10/13 试过一次，失败**：卡在 Eigen 下载阶段（`git clone` 没有超时设置，网络卡住时会无限等待，实测 7 分钟零字节）。待给 `fetch-eigen.ps1` 的 clone 加上低速超时（`-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30`）后重试
- [x] ~~提交验收材料~~ → ✅ 代码 + README + 测试 + [申报书](../submission/项目申报书.md)
- [ ] 报名季度评选

---

## 4. 任务分解（可直接建为 Issue）

| # | Issue | 标签 | 依赖 |
|---|---|---|---|
| 1 | 获取 Eigen 固定版本并提供可重复脚本 | `week1` `build` | — |
| 2 | `mb_eigen_shim_probe` 跑通，证明 C++17 + Eigen 进入构建 | `week1` `ffi` | 1 |
| 3 | 接入 ASan/UBSan 并纳入 CI | `week1` `test` | 2 |
| 4 | **判定 Plan A 是否可行**（`.cpp` 作 native-stub） | `week1` `spike` | 2 |
| 5 | 矩阵构造与数据搬运（`new`/`from_array`/`copy_to`） | `week2` `ffi` | 4 |
| 6 | 四则运算与转置 | `week2` `ffi` | 5 |
| 7 | 求解 / 行列式 / 范数 / 内积 + 奇异矩阵检测 | `week2` `ffi` | 6 |
| 8 | 单元测试补齐（含错误路径） | `week2` `test` | 7 |
| 9 | 校验 `#borrow` 语义并记录结论 | `week2` `spike` | 5 |
| 10 | `examples/solve` | `week3` `docs` | 7 |
| 11 | `examples/linreg` | `week3` `docs` | 7 |
| 12 | `examples/crosscheck`（与纯 MoonBit 实现对拍） | `week3` `docs` | 7 |
| 13 | `docs/DESIGN.md` + README 实测数据回填 | `week3` `docs` | 8 |
| 14 | Linux CI（含 `-lstdc++`） | `week3` `build` | 3 |
| 15 | 演示脚本 + 录屏 | `week4` `docs` | 10 |
| 16 | 干净环境复现验证 | `week4` `verify` | 15 |
| 17 | 验收材料提交 + 季度评选报名 | `week4` `submit` | 16 |

---

## 5. 风险与应对（单人版）

| 风险 | 概率 | 影响 | 应对 |
|---|---|---|---|
| `.cpp` 作 `native-stub` 不被接受 | **中** | 高 | 熔断 → Plan B（静态库 + `cc-link-flags`） |
| **Eigen 模板编译太慢拖垮迭代**（叠加 issue #2254） | **中高** | 中 | `/O1`；Eigen 使用集中在单一 `.cpp`；必要时上预编译头；`MOON_CC=clang` |
| clang-cl 参数/路径踩坑 | 中 | 中 | 预留 8 小时给穿刺；必要时改 VS Build Tools |
| `#borrow` 语义与预期不符导致崩溃 | 中 | 中 | 退回 owned 约定 + 显式 `moonbit_decref`；ASan 兜底 |
| 引用计数写错 → 崩溃/泄漏 | 中 | 中 | **ASan 第 1 周就接**；优先用 `#borrow`；先通最简调用再上复杂类型 |
| 18 天做不完 L0 | 中 | 中 | 降级阶梯 L1/L2；每周日检查进度 |
| 时间被"学语言"吃掉 | **高** | 中 | 边做边学；第 1 周就以跑通 FFI 为学习目标 |
| 被判定"MoonBit 不是主要实现语言" | 中 | **高** | C++ 侧刻意保持薄；MoonBit 侧承担错误处理/检查/格式化/示例/测试；v2 增加纯 MoonBit 功能 |
| 演示效果弱（单人无团队故事） | 中 | 中 | README 首屏放可运行代码 + 性能对比数据 + GIF |

---

## 6. v2 方向（若时间有余或下一期）

按"提升 MoonBit 侧占比"的思路排列：

1. **纯 MoonBit 的便捷构造器**：单位阵、对角阵、切片、reshape
2. **纯 MoonBit 的统计功能**：均值、方差、协方差、归一化（都是矩阵运算的组合，
   不需要碰 C++，却能显著提升"这是 MoonBit 库"的观感）
3. **特征值 / SVD / QR**（扩 C++ 边界，但 API 设计仍在 MoonBit）
4. **与 `moonbitlang/core` 生态对齐**：实现 `Show` / `Eq` 等 trait
5. **CSV / Matrix Market 文件读写**（纯 MoonBit 可做）

---

## 7. 每天固定动作

- 至少 1 次有意义的 commit，前缀 `feat:` / `fix:` / `docs:` / `test:` / `build:`
- 禁止 `update` / `fix` 这类无信息提交
- 关键决策记入 `docs/DECISIONS.md`（注明日期与理由）
- 每周在 Issue 里写"本周进展 + 下周计划"

**这些不是形式主义**：官方验收第 2 条要求"保留连续可追踪的提交记录"，
第 4 条要求"包含本期完成的实质新增工作" —— 提交历史本身就是评分材料。
