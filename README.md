# moonbit-eigen

> 把 C++ 生态最成熟的线性代数库 [Eigen](https://gitlab.com/libeigen/eigen) 带给 MoonBit。

MoonBit 侧是纯粹的 MoonBit 类型与 `Result`；Eigen 的模板、句柄、异常、
列主序存储全部被一层薄胶水挡在外面。

```moonbit
let a = match Matrix::from_array(2, 2, [2.0, 1.0, 1.0, 3.0]) { Ok(m) => m; Err(_) => abort("") }
let b = match Matrix::from_array(2, 1, [3.0, 5.0]) { Ok(m) => m; Err(_) => abort("") }
match a.solve(b) {
  Ok(x) => println(x.to_string())   // Matrix(2x1)
                                    //   [0.800]
                                    //   [1.400]
  Err(msg) => println("失败: \{msg}")
}
```

---

## 项目状态（2026-10-13）

**已全部跑通：Eigen 绑定本体、FFI 机制、单元测试与三个可运行示例。**

| 部分 | 状态 |
|---|---|
| MoonBit API 层、FFI 声明、3 个示例 | ✅ `moon check --target native` 通过（0 errors） |
| **FFI 机制全链路**：`.cpp` 作 native-stub、外部对象 + finalizer、`#borrow` 传参、错误哨兵约定、UTF-8 编码往返 | ✅ `moon test --target native selftest` — **7/7 通过** |
| **Eigen 绑定本体**（矩阵运算与错误路径） | ✅ `moon test --target native src` — **18/18 通过** |
| 三个可运行示例 | ✅ 均 exit 0：解方程得 `x = [0.8, 1.4]`；线性回归精确复原截距 1 / 斜率 2；与纯 MoonBit 实现对拍**最大误差 0** |
| ASan / UBSan | ⏳ 待接入 |

工具链与环境（本机实测）：

```
MoonBit   moon 0.1.20261012 / moonc v0.10.15
C++       VS Build Tools 18 · MSVC 14.51 · E:\VSBuildTools
Eigen     3.3.90（来自 GitHub libigl/eigen 镜像；见下方「来源与许可」的说明）
```

几条实测经验记录在 [docs/PITFALLS.md](docs/PITFALLS.md)：
`cc-flags` 与 `stub-cc-flags` 的语义差异、`moonbit_make_external_object` 取值必须解引用、
`/utf-8` 的必要性、`dot` 的形状断言 bug、以及"声明了 `native-stub` 的库包需要
按包名调用 moon"这一行为。

**⚠️ 一个使用注意**：请用 `moon test --target native src`（带包名）而不是
不带包名的整模块调用，原因见 [docs/PITFALLS.md](docs/PITFALLS.md) 第 10.2 节。

---

## 为什么需要它

MoonBit 目前**没有任何线性代数能力**：`moonbitlang/core` 里没有矩阵库，
mooncakes.io 上也没有 Eigen / Armadillo / BLAS / LAPACK 的任何绑定。

Eigen 是 C++ 世界里经过十几年验证的 header-only 线性代数库：
零依赖、只需包含头文件、性能接近手写 BLAS。
本项目把它接进 MoonBit，而不是重新实现一遍数值算法 ——
重复造轮子在数值领域尤其昂贵（数值稳定性是几十年踩坑的积累）。

---

## 架构

```
┌──────────────────────────────────────────────────────────┐
│ 用户代码 / examples/*.mbt                                 │
├──────────────────────────────────────────────────────────┤
│ src/eigen.mbt    MoonBit 公开 API 层（主要实现语言）        │
│   Matrix 类型、Result 错误处理、维度检查、格式化输出        │
├──────────────────────────────────────────────────────────┤
│ src/ffi.mbt      私有 extern "C" 声明层                    │
│   type EigenMatrix（抽象类型）/ #borrow / FixedArray[Double]│
├──────────────────────────────────────────────────────────┤
│ src/eigen_shim.cpp   ← 胶水层（薄）                        │
│   · 把 Eigen 模板实例化掉（MoonBit 侧无法完成的事）         │
│   · moonbit_make_external_object 生命周期 + finalizer      │
│   · 异常拦截：C++ 异常绝不跨越 ABI 边界                     │
│   · 行主序归一化：不让 Eigen 的列主序泄漏出去               │
├──────────────────────────────────────────────────────────┤
│ src/third_party/eigen/   Eigen（MPL2，脚本获取，不入库）    │
└──────────────────────────────────────────────────────────┘
```

**边界设计原则**：C++ 侧只做"MoonBit 做不到的事"（模板实例化、ABI 归一化、
生命周期桥接）。错误处理、维度检查、格式化、示例、测试全部在 MoonBit 侧 ——
这既符合官方验收"以 MoonBit 作为项目主要实现语言"的要求，
也让这个绑定真正是"MoonBit 的库"而不是"Eigen 的转写"。

---

## 快速开始

### 前置依赖

| 平台 | 要求 |
|---|---|
| Windows | MoonBit 工具链 + **LLVM（`clang-cl`）**。⚠️ **MinGW 不被 MoonBit native 后端支持** |
| Linux / macOS | MoonBit 工具链 + `gcc` 或 `clang` |

### 构建

```bash
# 1) 按固定版本获取 Eigen（不入库，见 .gitignore）
powershell -File scripts/fetch-eigen.ps1          # Windows
# bash scripts/fetch-eigen.sh               # Linux/macOS（W1 补齐）

# 2) 先验证 C++ 胶水真的被编进来了（一行自检，见 docs/ROADMAP.md 第 1 周）
moon test --target native selftest
moon test --target native src

# 3) 跑示例
moon run examples/solve --target native
```

Windows 上如果 native 构建出现"胶水符号找不到"之类的怪现象，
先强制走 C 后端再试（见 [docs/PITFALLS.md](docs/PITFALLS.md) 第 5.1 节）：

```powershell
$env:MOONBIT_NEW_NATIVE = "0"
moon test --target native src
```

---

## API

所有可能失败的操作用 `Result[T, String]` 返回，不抛异常 ——
调用方必须显式处理错误，跨语言边界的问题不会静默变成崩溃。

### 构造

| 方法 | 说明 |
|---|---|
| `Matrix::zeros(rows : Int, cols : Int) -> Result[Matrix, String]` | 全零矩阵 |
| `Matrix::from_array(rows, cols, data : Array[Double]) -> Result[Matrix, String]` | 从**行主序**数组构造，要求 `data.length() == rows * cols` |

### 访问

| 方法 | 说明 |
|---|---|
| `rows() -> Int` / `cols() -> Int` | 尺寸 |
| `get(i, j) -> Result[Double, String]` | 读元素 |
| `set(i, j, v) -> Result[Unit, String]` | 写元素 |
| `to_array() -> Result[Array[Double], String]` | 导出为行主序数组 |

### 运算

| 方法 | 说明 |
|---|---|
| `add(other)` / `sub(other)` | 要求尺寸相同 |
| `mul(other)` | 矩阵乘法，要求左列数 == 右行数 |
| `scale(k)` | 数乘 |
| `transpose()` | 转置 |
| `solve(b)` | 解 `Ax = b`，要求 `A` 为方阵；奇异矩阵返回 `Err` |
| `dot(other)` | 逐元素乘积之和（向量即点积） |
| `norm()` | Frobenius 范数 |
| `det()` | 行列式，要求方阵 |
| `to_string()` | 列对齐的多行渲染（**纯 MoonBit 实现**） |

---

## v1 能力边界（Limitations）

**刻意的范围控制，不是缺陷。** 明确的边界比含糊的承诺有用。

**不支持**：

- ❌ 稀疏矩阵
- ❌ 复数类型（当前只支持 `double`）
- ❌ 特征值 / SVD / QR 分解（v2 候选）
- ❌ 向量化 / SIMD 显式控制
- ❌ 回调式迭代（跨越 C ABI 传闭包风险高，v1 不做）
- ❌ 多线程并行（Eigen 本身需要 OpenMP 编译选项，v1 不开）

边界之外的需求请开 Issue。**说明理由比投赞成票更有用。**

---

## 示例

`examples/` 下提供（骨架已写，待工具链验证）：

- `examples/solve` —— 解线性方程组并打印过程，含错误路径演示（奇异矩阵、维度不匹配）
- `examples/linreg` —— 用正规方程做一元线性回归（数据由 `y = 2x + 1` 精确生成，结果可手算核对）
- `examples/crosscheck` —— **对拍**：用独立的纯 MoonBit 三重循环实现校验绑定的结果，
  同时验证行主序契约与数值正确性（原计划的性能对比 `bench` 改为本示例，
  理由见 `examples/crosscheck/moon.pkg` 的注释）

---

## 来源与许可

本项目**不复制** Eigen 源码入库。`scripts/fetch-eigen.ps1` 按**固定版本**从上游获取，
以便 CI 与本地拿到同一份代码，同时避免把数百个第三方文件放进本仓库。

| 组件 | 许可 | 说明 |
|---|---|---|
| **Eigen** | **MPL2**（部分文件为 MPL2 / LGPL3+ 双许可） | Copyright (c) Eigen authors · 官方仓库 <https://gitlab.com/libeigen/eigen> |
| **本项目原创代码** | **MIT**（见 [LICENSE](LICENSE)） | MoonBit API 层、胶水层、测试、文档 |

**关于实际使用的 Eigen 版本（如实说明）**：本机实测拿到的是 **3.3.90**，
不是 3.4.0 正式版 —— 脚本默认走 GitHub 的 `libigl/eigen` 镜像（因为
`gitlab.com` 在部分网络下不可达），该镜像的 master 版本号是 3.3.90
（Eigen 3.4 正式发布前的开发版本号）。获取脚本会在成功后**读出并打印
真实版本号**，并写入 `src/third_party/eigen/SOURCE.txt` 作为凭证。
本项目用到的 Eigen API 在 3.3 系列均已存在，18/18 测试通过。
若要严格使用 3.4.0 正式版，请在可访问 GitLab 的网络下走脚本的路径 A。

本项目是**绑定/移植类项目**，按赛事要求说明参考来源如下：

- 官方 C-FFI 教程（<https://moonbitlang.cn/pearls/moonbit-cffi>）—— FFI 写法的起点；
- 官方 agent skill `moonbit-c-binding` / `make-moonbit-c-bindings`
  （<https://github.com/moonbitlang/skills>）—— 目录布局、私有 extern、
  `moonbit.h` API 与 ASan 验证流程的参考；
- `illusory0x0/qpainter`（<https://github.com/moonbit-community/qpainter.mbt>）——
  生态里唯一的 C++ 绑定先例，本项目 Plan B 的构建方式参考自它。

---

## 文档

| 文档 | 内容 |
|---|---|
| [docs/TYPE_MAP.md](docs/TYPE_MAP.md) | **MoonBit ↔ C++ 类型与内存映射表**（本项目最有复用价值的部分） |
| [docs/PITFALLS.md](docs/PITFALLS.md) | 踩坑记录、已知 issue、待验证清单 |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 里程碑、熔断点、降级阶梯、任务分解 |

## 对照验收标准

本赛事的验收标准是**硬性判据**（不是评分维度），逐条对照如下：

| 验收要求 | 本项目的落实 |
|---|---|
| ① 以 MoonBit 作为主要实现语言 | C++ 侧只做 MoonBit 无法完成的事（模板实例化 / ABI 归一化 / 生命周期桥接）；错误处理、维度检查、格式化输出、示例、测试全部在 MoonBit 侧。理由与取舍见 [docs/DESIGN.md](docs/DESIGN.md) §2 |
| ② 仓库公开、连续可追踪的提交 | 每日有意义提交，规范见 [TEAM.md](TEAM.md)；关键决策逐条记入 [docs/DECISIONS.md](docs/DECISIONS.md) |
| ③ README + 可运行示例 + 必要测试 | 本文件 + `examples/solve` + `src/eigen_wbtest.mbt`（17 个测试，含 5 个错误路径）+ ASan/UBSan（[scripts/run-asan.sh](scripts/run-asan.sh)） |
| ④ 本期完成的实质新增工作 | 全部代码为本期新增，见 `git log` |
| ⑤ 开源许可证 + 说明来源 | MIT + 上方「来源与许可」一节（含 Eigen 的 MPL2） |
| ⑥ AI 可用，但目标/路径/质量由参赛者掌握 | 每条设计决策都在 [docs/DECISIONS.md](docs/DECISIONS.md) 里记录了理由与出处。**参赛者需在提交前通读全部实现并确认自己掌握它** |

> ⚠️ 本表在 10/28 终报前需按实际完成情况回填（尤其是 ③ 的测试与示例状态）
> 以及 ④ 的起止 commit 区间。

## 路线图

- [x] 选题论证（对比 CLI11 / toml++ / Eigen，见 PITFALLS §0）
- [x] 接口契约 + 类型映射表 + 仓库骨架
- [ ] **W1**：工具链穿刺 —— `.cpp` 能否作为 native-stub + ASan 接线
- [ ] **W2**：胶水层与 MoonBit API 打通并配齐单元测试
- [ ] **W3**：示例、性能对比、文档完善
- [ ] **W4**：演示脚本、验收材料

## 许可

MIT（本项目原创代码）。第三方组件许可见上文。

本项目是 2026 MoonBit 10 月黑客松参赛作品。
