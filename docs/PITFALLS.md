# 踩坑记录与未解问题

> 本文件是本项目对社区最有复用价值的部分之一。
> 每条都尽量给出**出处**；查不到出处的明确标注为"未证实"，不写成事实。

---

## 0. 选题阶段的两个决定性事实

### 0.1 `moonbitlang/core` 已经有 `argparse`

官方 core 的工具类里包含 `argparse`（与 `json`、`quickcheck`、`bench`、`test`、`debug`、`env` 并列）。

**影响**：官方验收标准明确写着"**重复提交、拆分项目或仅做简单修改，不计入验收与奖励**"。
再写一个命令行解析绑定，即便技术上是"绑定"而非"重写"，也很容易被判定为重复造轮子。
**这是我们放弃 CLI11、改做 Eigen 的直接原因。**

出处：<https://github.com/moonbitlang/core>（README 架构图）；验收标准见
<https://github.com/moonbitlang/Hackathon2026/blob/main/src/App.tsx>

### 0.2 Eigen 是确认的生态空白

逐条检索后，以下方向在 mooncakes.io 上**没有任何 C/C++ 绑定**：
Eigen、Armadillo、BLAS/LAPACK、SuiteSparse、nlohmann/json、OpenSSL、libcurl、
FFmpeg、Vulkan、WebGPU、libprotobuf、hiredis、ONNX Runtime、OpenCV 等。

其中 **Eigen 是 header-only、零依赖**，构建复杂度与普通头文件库相同，
但补上的是整个"线性代数"能力空白 —— 性价比最高。

出处：<https://mooncakes.io/api-new/v0/search?kw=raylib> 等检索接口（逐关键词实测）

---

## 1. C++ 没有官方绑定路径（本项目最大的技术风险）

**事实**：官方把 `native-stub` 定义为 **C** stub：

> The `native-stub` field lists **C** stub source files that should be compiled
> with this package for native builds.

文档**没有**承诺支持 `.cpp` / `.cc`。而且生态里唯一的 C++ 真实先例
`illusory0x0/qpainter`（关键词标了 "C++ FFI"）**根本没用 native-stub**：

```json
{
  "link": { "native": {
    "cc": "gcc",
    "cc-link-flags": "-Lbuild -lqpainter_mbt -lQt6Core -lQt6Gui -lQt6Widgets -lstdc++"
  }},
  "pre-build": [
    { "input": "../../stub/stub.cxx",
      "output": "../../build/libruntime_mbt.a",
      "command": "make native_stub" }
  ]
}
```

即：**C++ 胶水整个在 moon 的构建系统之外编译**（Makefile → 静态库 → `cc-link-flags`）。

**本项目的选择：Plan A / Plan B 双轨**

| 方案 | 做法 | 风险 |
|---|---|---|
| **Plan A** | `native-stub: ["eigen_shim.cpp"]` + `stub-cc: clang-cl`（.cpp 交 C++ 编译器） | 依赖未被官方承诺的行为，但配置最简 |
| **Plan B** | 脚本先把 `eigen_shim.cpp` 编成静态库，再 `cc-link-flags` 链进来 | 多一套构建，但是唯一有先例的路 |

先试 Plan A；`docs/ROADMAP.md` 的熔断点规定了何时切 Plan B。

出处：<https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html>（Native Stub Files）；
<https://github.com/moonbit-community/qpainter.mbt>；
<https://mooncakes.io/docs/illusory0x0/qpainter@0.3.1>

---

## 2. Windows 工具链政策锁死了可用编译器

**官方原文**：

> On Windows, the native backend requires an **MSVC-compatible toolchain with
> C++ tools and the Windows SDK**. Both Microsoft `cl.exe` and LLVM
> `clang-cl.exe` are supported. **MinGW toolchains are not supported.**

进一步地，相关 PR 会**拒绝包级的非 MSVC 覆盖**：

> …while still **rejecting package-level non-MSVC overrides** that would break
> the ABI contract.

**含义**：Windows 上 `link.native.cc` **不能**设成 `g++` / `clang++`，
只能是 `cl.exe` 或 `clang-cl.exe`。我们选 `clang-cl`（体积小、安装快）。

**逃生门**：`MOON_CC=clang`（注意不是 `clang++`）在实测中可用。

出处：<https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html>；
<https://github.com/moonbitlang/moon/pull/1852>；
<https://github.com/moonbitlang/moon/issues/2254>

---

## 3. `moonbit.h` 的 API 不确定性（最需要小心的地方）

### 3.1 不要用 `moonbit_make_string`

官方 2025-08 的黑板报文章里出现过 `moonbit_make_string`，但该符号在
**官方文档、官方 agent skill、GitHub issue 中均查不到出处**。

**我们的做法**：C 侧一律用 `moonbit_make_bytes` + `memcpy` 返回 UTF-8 字节，
MoonBit 侧用 `@utf8.decode_lossy` 解码 —— 这是官方 agent skill 推荐的做法。
副作用是好的：C++ 侧完全不需要处理 UTF-16。

### 3.2 导出函数必须加 `MOONBIT_FFI_EXPORT`

> **所有导出函数必须加这个宏**，否则 MoonBit 的链接器看不到它。

漏掉的症状是链接期"未定义符号"，而不是编译错误。
本项目在 `eigen_shim.cpp` 里对每个导出函数都加了它，
并做了 `#ifndef` 兜底以免某个版本没定义该宏时整文件编不过。

### 3.3 external object 的容器**不能**自己 free

> `finalize` **must not** drop the object itself, as this is handled by
> MoonBit runtime.

`finalize` 只负责释放 payload 里持有的外部资源（本项目里是 `delete MatrixBox`）。
另外：**不要用 `moonbit_make_bytes` 装含内部指针的 struct** —— Bytes 没有 finalizer，
内部堆分配会直接泄漏。

### 3.4 抽象类型 vs `#external`

`moonbit_make_external_object` 返回的对象，MoonBit 侧必须绑到**抽象类型**（`type T`），
**不能**用 `#external` —— 否则内存管理系统会忽略它，finalizer 永远不会跑。
（`#external` 的语义是"外部指针，MoonBit 不做任何引用计数"，正好相反。）

出处：<https://docs.moonbitlang.com/en/latest/language/ffi.html>（Lifetime management）；
<https://moonbitlang.cn/pearls/moonbit-cffi>；
官方 skill `moonbit-c-binding`：<https://github.com/moonbitlang/skills/tree/master/skills/moonbit-c-binding>

---

## 4. 引用计数：默认 owned，且语义正在迁移

- C 后端用**编译器优化的引用计数**（不是 tracing GC）。
- 默认是 **owned** 约定：**被调用方**负责 `moonbit_decref` 自己的参数。
- 官方明确警告：**默认语义正在从 `#owned` 迁移到 `#borrow`**。
- `#borrow` 的规则表：读字段 nothing / 存入数据结构 incref / 传给 MoonBit 函数 incref /
  传给其他 C 函数 nothing / **返回 incref** / 作用域结束 nothing。

**本项目采用 `#borrow`**，因为 shim 只在调用期间读取参数、不保存引用
（这一点很关键：**只要 C 侧可能保存指针，就绝对不能用 `#borrow`**，
否则 GC 回收后 C 侧会拿到悬垂引用）。

**已知风险**：`#borrow` 对 `FixedArray[Double]` 参数是否在所有版本都生效，需要实测。
若崩溃，退回到 owned 约定 + 在 shim 里显式 `moonbit_decref`。

出处：<https://docs.moonbitlang.com/en/latest/language/ffi.html>

---

## 5. 已知的 moon 工具链 issue（会影响本项目）

| Issue | 内容 | 我们的应对 |
|---|---|---|
| [#586](https://github.com/moonbitlang/moon/issues/586) | `cc-flags`/`cc-link-flags` 相对 **pwd** 而非包根目录解析 | **cc-flags 里不放任何路径**；Eigen 用相对包含 `"third_party/eigen/Eigen/Dense"`。若必须用 `-I`，用**绝对路径** |
| [#637](https://github.com/moonbitlang/moon/issues/637) | native 下 `moon run` 与 `moon test` 需要互相矛盾的 linker 配置（仍 open） | 若 `moon test` 与 `moon run` 只能活一个，优先让 `moon test` 通过（验收要求"必要测试"） |
| [#2254](https://github.com/moonbitlang/moon/issues/2254) | `cl /O2` 编译 moonc 生成的单文件（含 18.5k 行 `moonbit_init`）约 **100 秒**，MSVC 14.51 再退化 1.4–1.6× | 缓解：`/d2ReducedOptimizeHugeFunctions`（120s→32s）或 `MOON_CC=clang`。**这是迭代速度的头号威胁** |
| [#2262](https://github.com/moonbitlang/moon/issues/2262) | 未传 `-ffp-contract=off`，GCC 会做 FMA 收缩导致浮点结果与其他后端不一致 | 数值库对浮点一致性敏感，记入已知差异 |
| [#1201](https://github.com/moonbitlang/moon/issues/1201) | Windows 曾用 *nix `shlex` 解析命令串，而 Windows 是原样传给 `CreateProcessA` | 引号规则不同，cc-flags 里避免复杂引号（已 closed） |

### 5.1 Linux/Debug 构建可能不走 C 后端

> In v0.10.4, debug builds use the new native backend by default on macOS Apple
> Silicon, while release builds use the C backend with optimization. Set
> `MOONBIT_NEW_NATIVE=0` to force the C backend.

**本项目的 FFI 依赖 C 后端的行为**。若 native 构建出现"胶水符号找不到"之类的怪现象，
第一件事就是 `MOONBIT_NEW_NATIVE=0` 强制走 C 后端再试。

出处：<https://docs.moonbitlang.com/en/latest/language/ffi.html>（Backends）

---

## 6. Eigen 特有的坑

| 坑 | 说明 | 应对 |
|---|---|---|
| **模板无法跨 ABI** | Eigen 的 API 几乎全是模板，`extern "C"` 边界上无法表达 | 在 C++ 侧把模板**实例化**掉，边界只暴露 `MatrixXd` 的具体运算 |
| **默认列主序** | `Eigen::MatrixXd` 默认 column-major，而 MoonBit 数组直觉是行主序 | 所有搬运都按 `(i, j)` 逐元素进行，统一对外行主序，不让隐含约定泄漏 |
| **编译时间** | 一个 TU 包含 `<Eigen/Dense>` 并实例化若干运算，`/O2` 下可达数十秒，叠加 issue #2254 会更慢 | 用 `/O1`；把 Eigen 使用集中在单一 `.cpp`；必要时上预编译头 |
| **断言行为随 NDEBUG 变化** | Eigen 的尺寸断言在 release 下会被关闭，越界不报错而是 UB | **不依赖 Eigen 断言做校验**：所有维度/越界检查由我们在 shim 与 MoonBit 两侧显式做 |
| **异常** | Eigen 会抛 `std::bad_alloc`，`partialPivLu().solve()` 对奇异矩阵不抛而是返回非有限值 | shim 里 try/catch 全包；解方程后用 `allFinite()` 主动检测奇异 |
| **许可证** | Eigen 是 **MPL2**，且大量文件为 "Copyright (c) Eigen authors" 的双许可（MPL2 / LGPL3+）组合 | 验收要求"说明移植或参考来源"，见 README 的「来源与许可」一节 |

---

## 7. 官方验收标准带来的设计约束

从赛事源码取得的 6 条验收标准（原文要点）：

1. **以 MoonBit 作为项目主要实现语言**
2. 仓库公开、**保留连续可追踪的提交记录**
3. 提供清晰 README、**可运行示例**与**必要测试**
4. 已有项目必须包含**本期完成的实质新增工作**
5. 使用认可的开源许可证，并**说明移植或参考来源**
6. 可用 AI 辅助，但目标/路径/质量必须由参赛者掌握

**对设计的影响（很重要）**：

- **第 1 条**是绑定类项目最容易踩的雷：如果代码量主要集中在 C++ 胶水层，
  就有"MoonBit 不是主要实现语言"的风险。
  → 因此本项目把**错误处理、维度检查、格式化输出、示例、测试全部放在 MoonBit 侧**，
  并计划后续加入纯 MoonBit 的数值功能（见 ROADMAP 的 v2 方向）。
  C++ 侧刻意保持薄：只做模板实例化与 ABI 归一化。
- **第 5 条**要求写明来源与许可 → README 专设「来源与许可」一节，
  并明确 Eigen 的 MPL2 与本项目的 MIT 如何共存。
- **第 3 条**要求"可运行示例" → 见 `examples/`，不能只有测试。

出处：<https://github.com/moonbitlang/Hackathon2026/blob/main/src/App.tsx>；
<https://moonbitlang.github.io/Hackathon2026/>

---

## 8. 待验证清单（工具链就绪后逐项确认）

按优先级排列：

- [ ] `.cpp` 能否作为 `native-stub` 被接受（**决定 Plan A/B**）—— 仍需 C++ 工具链
- [x] ~~`moonbit.h` 里 `moonbit_make_bytes` 的确切签名~~ → 本机头文件确认：
      `moonbit_bytes_t moonbit_make_bytes(int32_t size, int value)`
- [x] ~~`MOONBIT_FFI_EXPORT` 的定义~~ → `__declspec(dllexport)`（Windows）/ 空（其他平台）
- [x] ~~`moonbit_make_external_object` 的签名~~ → 本机头文件确认
      `void *moonbit_make_external_object(void (*finalize)(void *self), uint32_t payload_size)`；
      注释明确 "finalize MUST NOT drop the container itself"
- [x] ~~`Moonbit_array_length` / `moonbit_incref` / `moonbit_decref`~~ → 均存在于本机头文件
- [ ] `#borrow` 用于 `FixedArray[Double]` 参数是否生效、有无崩溃 —— 需运行期验证
- [ ] Eigen 相对包含路径是否可行 —— 需实际编译
- [ ] `moon test` 与 `moon run` 在 `cc-link-flags` 为空时是否都正常（issue #637）
- [ ] 是否需要显式链接 C++ 运行时（当前留空）
- [x] ~~`@utf8.decode_lossy` 的确切包路径与函数名~~ → 已确认：`BytesView` 入参，已修正调用
- [x] ~~`FixedArray::make(len, init)` 的签名~~ → 已确认（官方 core 内部即如此使用）
- [x] ~~`Array::length()`~~ → 已确认；`String::contains` / `String::length` 仍未确认，
      测试已改为依赖已确认的 `Eq for String` 做断言
- [x] ~~`_wbtest.mbt` 与 `_test.mbt` 的实际可见性差异~~ → 官方文档已明确（见 DECISIONS D9）
- [ ] 若将来要加 BlackBox 测试，当前包的别名是否为 `@src`（v2 项，非阻塞）
- [x] ~~`Result[T, String]` 的 `match` 写法~~ → 官方 core 内大量使用，已确认

**本轮通过读取 core 的接口清单（`pkg.generated.mbti`）与源码而确认的 API**：

- ✅ `FixedArray::make(len, init)` —— 官方 core 内部正是这样用的
  （`let array = FixedArray::make(length, value(0))`）。
- ✅ `Array::length` / `Array::push` / `Array::from_fixed_array` 均存在。
- ✅ `pub impl Eq for String`、`pub impl Add for String` —— 所以字符串可用
  `==` / `!=` 比较、用 `+` 拼接。
- ⚠️ **`FixedArray::from_array` 收的是 `ArrayView[T]` 而不是 `Array[T]`**
  （`pub fn[T] FixedArray::from_array(array : ArrayView[T]) -> FixedArray[T]`）——
  我最初那版写法会失败，上一轮换成手写循环是对的。
- ⚠️ **`@utf8.decode_lossy` 收的是 `BytesView` 而不是 `Bytes`**
  （`pub fn decode_lossy(BytesView, ignore_bom? : Bool) -> String`）——
  已改为 `mb_eigen_last_error()[:]` 显式取视图。
- ❓ `String::contains` / `String::length` **未能在清单中确认**（builtin 的
  `.mbti` 有 74KB，抓取在 100KB 处被截断）。因此测试改用 `Eq for String`
  做断言，避免依赖这两个符号。

**本轮通过核实官方源码而确认的语法**（证据：`moonbitlang/core` 的 `double/moon.pkg`
与 `json/moon.pkg`，经 base64 解码读取原文）：

- ✅ **包导入路径 = `<模块名>/<包目录>`**。core 里写作 `"moonbitlang/core/double"`
  （模块名 `moonbitlang/core`），因此本项目的 `"moonbit-eigen/src"` 写法正确。
- ✅ **`builtin` 需要显式 import**。连 core 自己的包都写 `"moonbitlang/core/builtin"`，
  否则触发 `core_package_not_imported` 警告（警告 id 71）。已补进 `src/moon.pkg` 与三个示例。
- ✅ **别名语法** `"path" @alias`、**测试专用导入** `} for "test"` / `} for "wbtest"`
  的写法均与官方一致（本项目暂未用到后两者）。
- ✅ `_test.mbt`(BlackBox) / `_wbtest.mbt`(WhiteBox) 的可见性差异有官方文档明确说明
  （见 DECISIONS D9），不再是"待验证"。

**已在本轮通过改用基础语法而消除的不确定符号**（见 DECISIONS D8）：

- ✅ ~~`FixedArray::from_array`~~ → 改为 `FixedArray::make` + 下标赋值
- ✅ ~~`Array::from_fixed_array`~~ → 改为 `Array::push` 循环
- ✅ ~~`StringBuilder::new / write_string / write_char / to_string`~~ → 改为 `String` 拼接
- ✅ ~~`Double::round / to_int / to_double`~~ → 随格式化函数一并删除

**当前仍依赖的标准库符号（全部为语言基础或官方文档出现的）**：
`FixedArray::make`、数组下标读写、`Array::push` / `Array::length`、
`String` 拼接与 `\{expr}` 插值、`Result` / `Ok` / `Err` / `match`、
`abort`、`test` 块、`@utf8.decode_lossy`。
- [ ] 是否需要在 CI（Linux/gcc）上加 `-lstdc++`

**✅ 已由 `moon check` 验证**（moonc v0.10.15）：

- 全部 MoonBit 代码通过类型检查 —— API 层、FFI 声明、17 个测试、3 个示例。
  命令：`moon check --target native`（在模块根目录执行，输出 `0 errors`）。

---

## 9. 本机环境诊断（2026-10-13 实测）

用 `moon check` 把此前"凭推理写下的代码"过了一遍，结果推翻了若干假设。
完整的 4 处真问题记录在 [DECISIONS.md](DECISIONS.md) D13，这里只留可操作的部分。

### 9.1 环境现状

| 组件 | 状态 |
|---|---|
| MoonBit 工具链 | ✅ 已装（`moon 0.1.20261012` / `moonc v0.10.15`），位于 `%USERPROFILE%\.moon\bin` |
| `.moon\bin` 在 PATH 中 | ❌ 否 —— 需用完整路径，或把它加进 PATH |
| `moonbit.h` | ✅ `%USERPROFILE%\.moon\include\moonbit.h`（9955 字节） |
| **C++ 工具链** | ❌ **缺**。装了 VS Build Tools 18，但**没有 C++ 工作负载**（找不到 `cl.exe`；`vswhere -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64` 返回空） |
| LLVM / clang-cl | ❌ 未安装 |
| MinGW g++ | ✅ 有，但 **MoonBit 官方明确不支持**，用不了 |
| Eigen | ❌ 未获取（需 `pwsh -File scripts/fetch-eigen.ps1`） |

缺 C++ 工具链时 moon 的报错（可作判断依据）：

```
Windows native backend requires MSVC Build Tools with C++ tools and Windows SDK
```

### 9.2 三条"只有编译器能告诉你"的规则

1. **`moon.mod.json` 已不再被支持**，必须用 `moon.mod`（`moon fmt` 可自动迁移）。
   本机版本带 `rr_moon_mod` 特性开关。
2. **extern 的指针参数必须标注 `#borrow` / `#owned`**，否则是 **error 55**（错误，非警告）。
   默认约定目前是 `#owned`，即**被调用方必须 decref 自己的参数** ——
   我们的 shim 不做 decref，所以必须标 `#borrow`，否则对象永不回收、finalizer 不触发。
3. **`moon.mod` 里的 `source = "src"` 会把该目录之外的包静默排除**：
   `examples/` 下的包不报错、也不被检查。移除该字段后示例才被纳入。

### 9.3 一条方法论教训

> **"检查通过"不等于"被检查过"。**

`source = "src"` 就是典型：`moon check` 一直返回绿色，
但三个示例包**从未被检查**。发现方式是往示例里**故意注入一个类型错误**，
看检查是否报错 —— 不报，就说明覆盖范围有问题。

**验证覆盖范围本身，也需要被验证。**

### 9.4 ⚠️ 更正：`moonbit_make_string` 确实存在

前面几版文档写过"`moonbit_make_string` 在官方文档/skill/issue 中查不到出处、
不要使用"。**这个结论是错的** —— 本机 `moonbit.h` 第 185 行明确声明：

```c
MOONBIT_EXPORT moonbit_string_t moonbit_make_string(int32_t size, uint16_t value);
MOONBIT_EXPORT moonbit_string_t moonbit_make_string_raw(int32_t size);
```

教训：**"我在公开资料里没搜到" ≠ "它不存在"。**
判断一个 C 侧运行时 API 是否存在，最权威的地方是**本机的
`$MOON_HOME/include/moonbit.h`**，而不是搜索结果。

**实现不需要改**：仍用 `moonbit_make_bytes` + MoonBit 侧 `@utf8.decode_lossy`，
因为这是官方 agent skill 推荐的做法（且避免 C++ 侧处理 UTF-16）。
但**理由要改**：不是"那个 API 不存在"，而是"这条路径更符合官方推荐、也更省事"。
