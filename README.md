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
| **FFI 机制全链路**：`.cpp` 作 native-stub、外部对象 + finalizer、`#borrow` 传参、错误哨兵约定、UTF-8 编码往返 | ✅ `moon test --target native selftest
# 纯 MoonBit 参考实现自己的测试（不依赖 Eigen）
moon test --target native reference` — **7/7 通过** |
| **Eigen 绑定本体**（矩阵运算与错误路径） | ✅ `moon test --target native src` — **18/18 通过** |
| 三个可运行示例 | ✅ 均 exit 0。`crosscheck` 做 **5 组对拍**全部一致：矩阵乘法误差 `0`；**解方程（2×2 与 3×3）与独立实现吻合到 `2.2e-16`**；行列式 `5` / `-3`；奇异矩阵两边都正确拒绝 |
| **ASan（AddressSanitizer）** | ✅ **已接入并实测通过**（Windows/MSVC）：18/18 测试在 ASan 生效下通过，且校验过产物确实引用 `clang_rt.asan`（防假绿）。配方、`0xc0000135` 这个坑与三道断言见 [docs/PITFALLS.md](docs/PITFALLS.md) 第 12 节 |

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

MoonBit 生态里**已经有纯 MoonBit 的线性代数包**
（如 [Luna-Flow/linear-algebra](https://github.com/Luna-Flow/linear-algebra)、
[moonbit-community/linalg](https://github.com/moonbit-community/linalg)），
但**没有把成熟的原生数值栈接进来的绑定**：`moonbitlang/core` 没有矩阵库，
mooncakes.io 上检索不到 Eigen / Armadillo / BLAS / LAPACK 的任何绑定。

**两者的关系是互补而非替代**：纯 MoonBit 实现可控、可读、可跨后端；
绑定则直接复用几十年验证过的算法与优化。本项目补上的是后一条路径 ——
它的产物（`Matrix` 绑定）原则上可以作为前者的原生后端。

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

### 实现代码构成（可自行复现）

| 语言 | 文件 | 行数 | 占实现代码 |
|---|---|---|---|
| **MoonBit（`.mbt`）** | 11 | **1645** | **70%** |
| C++（`.cpp` / `.hpp`） | 3 | 716 | **30%** |

C++ 那 716 行里，大头是"把 Eigen 模板实例化掉 + 逐元素搬运 + 错误哨兵"，
它**不包含任何数值算法** —— 算法全在 Eigen 里。

> GitHub 页面顶部的语言彩条按**字节**统计，会把构建脚本（PowerShell / Shell）
> 和注释也算进去，且中文注释在 UTF-8 下每字符占 3 字节，因此那根彩条
> （MoonBit 约 37%、C++ 约 30%）**低于** MoonBit 在实际实现代码中的占比。
> 上面这张表按**实现代码行数**统计，更能反映"谁是这个项目的主要实现语言"。

复现方式（排除第三方依赖与构建产物）：

```powershell
# Windows PowerShell
Get-ChildItem -Recurse -Include *.mbt,*.cpp,*.hpp -File |
  Where-Object { $_.FullName -notmatch 'third_party|_build' } |
  Group-Object Extension |
  ForEach-Object { "{0,-6} {1,5} 行" -f $_.Name, (($_.Group | Get-Content | Measure-Object).Count) }
```

```bash
# Linux / macOS
for e in mbt cpp hpp; do
  printf '%-6s %5s 行\n' ".$e" \
    "$(find . -name "*.$e" -not -path '*/third_party/*' -not -path '*/_build/*' -exec cat {} + | wc -l)"
done
```

未计入：`scripts/`（构建工具）、`docs/`（文档）、`.github/`（CI 配置）。

---

## 快速开始

### 前置依赖

| 平台 | 要求 | 验证状态 |
|---|---|---|
| **Windows** | MoonBit 工具链 + **MSVC**（Visual Studio 的 C++ 工作负载，`cl.exe` 无需在 PATH 上，moon 用 `vswhere` 自动发现）。⚠️ **MinGW 不被 MoonBit native 后端支持** | ✅ **本项目的开发与验证平台** |
| Linux / macOS | MoonBit 工具链 + `gcc`/`clang` | ⚠️ **只能通过 `moon check` 类型检查**，见下 |

> **⚠️ 关于 Linux / macOS（如实说明）**
>
> 本项目**只在 Windows + MSVC 上做过完整的构建与运行验证**。
> 在 Linux 上 `moon check`（纯类型检查）可以通过，但**原生构建需要先改配置**：
>
> `src/moon.pkg` 的 `stub-cc-flags` 里是 MSVC 专用选项
> （`/EHsc /utf-8 /bigobj /O1`），**GCC 一个都不认**；同时 GCC 驱动不会
> 自动链接 `libstdc++`，需要在 `cc-link-flags` 里加 `-lstdc++`。
> 正确做法是把 `stub-cc-flags` 换成 `-std=c++17 -fexceptions` 之类，
> 并补上 `-lstdc++`。
>
> `scripts/run-asan.sh` 里演示了这个替换动作。之所以不做成自动切换：
> **`moon.pkg` 是静态配置，无法按操作系统分支**（moon 只支持按后端与
> 优化级别设置条件），这是本项目在跨平台上的已知取舍。
>
> 因此本仓库的 `.sh` 脚本都标注为「未在开发机验证」——
> 与其给你一个看起来能跑但没验证过的脚本，不如把状态说清楚。

### 构建

```bash
# 1) 按固定版本获取 Eigen（不入库，见 .gitignore）
powershell -File scripts/fetch-eigen.ps1          # Windows
# bash scripts/fetch-eigen.sh               # Linux/macOS（W1 补齐）

# 2) 先验证 C++ 胶水真的被编进来了（一行自检，见 docs/ROADMAP.md 第 1 周）
moon test --target native selftest
# 纯 MoonBit 参考实现自己的测试（不依赖 Eigen）
moon test --target native reference
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

仓库里的包（每个都是独立可测的单元）：

| 包 | 类型 | 作用 |
|---|---|---|
| `src/` | 库 | 绑定的公开 API 层 + FFI 声明层（含 18 个测试） |
| `reference/` | 库 | **纯 MoonBit 的线性代数参考实现**，零第三方依赖，用作绑定的独立对拍对象（含 13 个测试） |
| `selftest/` | 库 | FFI 机制自检，不依赖 Eigen，用来独立回答"MoonBit 能不能调用 C++"（含 7 个测试） |
| `examples/` | 可执行 | 三个示例（解方程 / 线性回归 / 对拍） |

`examples/` 下提供：

- `examples/solve` —— 解线性方程组并打印过程，含错误路径演示（奇异矩阵、维度不匹配）
- `examples/linreg` —— 用正规方程做一元线性回归（数据由 `y = 2x + 1` 精确生成，结果可手算核对）
- `examples/crosscheck` —— **对拍**：用 `reference/` 包里独立的纯 MoonBit 实现校验绑定的结果（5 组：乘法、2×2 与 3×3 解方程、行列式、奇异矩阵判定），
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
| [docs/CPP_BINDING_GOTCHAS.md](docs/CPP_BINDING_GOTCHAS.md) | **写给 MoonBit 社区：接 C++ 库时踩过的 12 个坑** —— 全部来自本项目实测，附一页速查表。**想写 C++ 绑定的人建议先看这篇** |
| [docs/TYPE_MAP.md](docs/TYPE_MAP.md) | **MoonBit ↔ C++ 类型与内存映射表**（本项目最有复用价值的部分） |
| [docs/PITFALLS.md](docs/PITFALLS.md) | 本项目的逐条踩坑记录、已知 issue、待验证清单 |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 里程碑、熔断点、降级阶梯、任务分解 |
| [docs/SCRIPTS.md](docs/SCRIPTS.md) | `scripts/` 下每个脚本的作用、平台、实测状态与设计理由 |
| [docs/DESIGN.md](docs/DESIGN.md) | ABI 边界为什么这样切 |
| [docs/DECISIONS.md](docs/DECISIONS.md) | 逐条设计决策（含日期与理由） |

## 对照验收标准

本赛事的验收标准是**硬性判据**（不是评分维度），逐条对照如下：

| 验收要求 | 本项目的落实 |
|---|---|
| ① 以 MoonBit 作为主要实现语言 | C++ 侧只做 MoonBit 无法完成的事（模板实例化 / ABI 归一化 / 生命周期桥接）；错误处理、维度检查、格式化输出、示例、测试全部在 MoonBit 侧。理由与取舍见 [docs/DESIGN.md](docs/DESIGN.md) §2 |
| ② 仓库公开、连续可追踪的提交 | 仓库**公开**；**26 个提交**按工作单元拆分（骨架 → 类型检查 → 测试 → ASan → 文档 → 示例 → 对拍），全部为本期完成。⚠️ 早期骨架在**同一个会话内**批量产出（提交时间集中在同一天），这一点已在 [TEAM.md](TEAM.md) 中如实说明，未做任何粉饰；关键决策逐条记入 [docs/DECISIONS.md](docs/DECISIONS.md) |
| ③ README + 可运行示例 + 必要测试 | 本文件 + **三个可运行示例**（[examples/solve](examples/solve) / [linreg](examples/linreg) / [crosscheck](examples/crosscheck)）+ 共 **38 个测试**（`src` 18 个含错误路径 + `reference` 13 个 + `selftest` 7 个，全部已实测通过）+ ASan（[scripts/run-asan.ps1](scripts/run-asan.ps1) 在 Windows/MSVC 上**已实测生效**；[scripts/run-asan.sh](scripts/run-asan.sh) 为 GCC 语法版本，**尚未在开发机验证**，本机无 Linux 环境） |
| ④ 本期完成的实质新增工作 | 仓库为本期**新建**：全部 26 个提交都在本期（`0c22fe4` → `4f6604f`，见 `git log`）。没有历史代码，也没有从别处拷贝的实现 |
| ⑤ 开源许可证 + 说明来源 | MIT + 上方「来源与许可」一节（含 Eigen 的 MPL2） |
| ⑥ AI 可用，但目标/路径/质量由参赛者掌握 | 每条设计决策都在 [docs/DECISIONS.md](docs/DECISIONS.md) 里记录了理由与出处。**参赛者需在提交前通读全部实现并确认自己掌握它** |

> **本表状态（2026-10-13 实测）**：① ② ⑤ ⑥ 已达成；③ 的测试、三个示例与 ASan
> 均已实测（38/38）；④ 的提交区间为本期全部提交。
>
> 终报（10/28）前若继续开发（候选：特征值与 SVD/QR、Linux 构建、ASan 接入 CI），
> 需同步更新本表与上方的「项目状态」。

## 路线图

- [x] 选题论证（对比 CLI11 / toml++ / Eigen，见 PITFALLS §0）
- [x] 接口契约 + 类型映射表 + 仓库骨架
- [x] **W1**：工具链穿刺 —— `.cpp` 能否作为 native-stub + ASan 接线
- [x] **W2**：胶水层与 MoonBit API 打通并配齐单元测试 —— ✅ `src` 18/18（含错误路径）
- [x] **W3**：示例、文档完善 —— ✅ 三个示例 + 8 份文档；原计划的性能对比改为「跨语言对拍」（理由见 `examples/crosscheck/moon.pkg` 注释）
- [x] **W4**：演示脚本、验收材料 —— ✅ `demo.ps1` 8 步全过 + [申报书](submission/项目申报书.md)

## 许可

MIT（本项目原创代码）。第三方组件许可见上文。

本项目是 2026 MoonBit 10 月黑客松参赛作品。
