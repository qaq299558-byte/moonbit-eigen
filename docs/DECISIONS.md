# 设计决策记录

> 格式：每条记录**日期 + 决策 + 理由 + 出处**。
> 官方验收第 2/4 条看重可追踪的实质工作，决策记录是最直接的证据之一。

---

## D1 · 2026-10-13 · 选题从 CLI11 改为 Eigen

**决策**：项目目标从"绑定 C++ 命令行解析库 CLI11"改为"绑定 C++ 线性代数库 Eigen"。

**理由**：

1. 检索确认 `moonbitlang/core` **已经包含 `argparse`**。而官方验收标准明确写着
   "**重复提交、拆分项目或仅做简单修改，不计入验收与奖励**" ——
   再做一个命令行解析绑定，有被判定为"重复造轮子"而不计入验收的实质风险。
   这是淘汰级风险，优先级高于任何技术风险。
2. 检索确认 **Eigen 是生态空白**：mooncakes.io 上没有 Eigen / Armadillo /
   BLAS / LAPACK 的任何绑定，core 也没有矩阵能力。
3. 两者的**技术风险相当**：都是 header-only、零依赖、不需要额外构建系统。
   但 Eigen 补上的是整个"线性代数"能力，价值高一个量级。
4. Eigen 是重度模板库，"如何把模板库绑定到 MoonBit"本身就是一个
   比"绑定一个普通类库"更有技术含量、更值得写成文档的题目。

**放弃的备选**：`toml++`（配置解析，模板重、价值一般）、
`nlohmann/json`（core 已有 JSON，价值不清晰）。

**出处**：<https://github.com/moonbitlang/core>（core 的 `argparse`）；
<https://github.com/moonbitlang/Hackathon2026/blob/main/src/App.tsx>（验收标准）；
mooncakes.io 检索接口（空白确认）。

---

## D2 · 2026-10-13 · 跨边界字符串统一用 Bytes，不用 `moonbit_string_t`

**决策**：C 侧用 `moonbit_make_bytes` + `memcpy` 返回 UTF-8 字节，
MoonBit 侧用 `@utf8.decode_lossy` 解码。

**理由**：官方 2025-08 黑板报文章用的是 `moonbit_make_string`，
但该符号在**官方文档、官方 agent skill、GitHub issue 中均查不到出处**。
官方 agent skill 明确推荐的是 `moonbit_make_bytes` + MoonBit 侧解码这条路。

**附带收益**：C++ 侧完全不需要处理 UTF-16 转换，中文路径不会出乱码。

**代价**：多一次解码，但错误信息不在热路径上，无影响。

---

## D3 · 2026-10-13 · 失败返回"错误哨兵"而非 `nullptr`

**决策**：返回句柄的 C 函数永远返回一个真实、可安全回收的外壳对象；
失败时该对象 `valid == false`，MoonBit 侧用 `rows() == -1` 识别。

**理由**：MoonBit 侧把返回句柄绑到**抽象类型**，抽象类型没有 null 语义。
返回 `nullptr` 会让 MoonBit 拿到一个数值为 0 的"句柄"，任何操作都是未定义行为，
而且崩在离出错点很远的地方，极难排查。

**备选方案及否决理由**：用 `Ref[T]` 出参（需要引入一层未验证机制）；
返回负状态码 + 查询（调用方容易忘记检查）。

---

## D4 · 2026-10-13 · C++ 胶水采用 Plan A / Plan B 双轨

**决策**：优先用 `native-stub: ["eigen_shim.cpp"]`（Plan A）；
若不可行，改用脚本预编译静态库 + `cc-link-flags`（Plan B）。

**理由**：官方把 `native-stub` 定义为 "**C** stub source files"，
未承诺支持 `.cpp`。而生态里唯一的 C++ 真实先例 `illusory0x0/qpainter`
**根本没用 native-stub**，走的是 `pre-build` + Makefile + 静态库这条路。

先试 Plan A 是因为配置最简；但必须预设 Plan B，并在 10/19 设熔断点。

---

## D5 · 2026-10-13 · 不用 `supported-targets: ["native"]`

**决策**：改用 `targets: { "ffi.mbt": ["native"] }` 逐文件门控。

**理由**：官方 agent skill 明确劝阻 `supported-targets: ["native"]` ——
它会阻止下游包在其它后端构建。逐文件门控能达到同样目的而不损害下游。

---

## D6 · 2026-10-13 · 对外统一行主序

**决策**：所有矩阵数据搬运按 `(i, j)` 逐元素进行，MoonBit 侧看到的永远是行主序。

**理由**：`Eigen::MatrixXd` 默认是**列主序**。若直接 `memcpy` 整块内存，
就会把 Eigen 的存储约定泄漏到 MoonBit 侧，成为极难发现的 bug。
逐元素搬运的代价在小规模下可忽略，换来的是明确的语义契约。

---

## D7 · 2026-10-13 · CI 只跑 ubuntu-latest

**决策**：GitHub Actions 只在 Linux 上跑测试；Windows（clang-cl）的构建
说明写进 README，靠本地验证 + 录屏留证。

**理由**：Windows 上必须使用 MSVC 兼容工具链（MinGW 被官方排除），
在 CI 里配它成本高、收益低；单人项目没有时间为跨平台 CI 矩阵买单。
而验收要的是"可复现"，README + 录屏足以证明。

---

## D8 · 2026-10-13 · `to_string` 只用字符串拼接，不引入未验证 API

**决策**：`Matrix::to_string` 仅使用最基础的字符串拼接（`+`）与 Show 插值
（`"\{expr}"`）构建输出。

**修订过程（值得记录）**：初版用 `StringBuilder::new / write_string / write_char /
to_string` 加一个手写的 `format_double`（依赖 `Double::round / to_int / to_double`）
来做列对齐输出。第二轮复核时改为字符串拼接，原因是：

1. 复核确认 MoonBit 有 `_test.mbt`（BlackBox）与 `_wbtest.mbt`（WhiteBox）两种测试语义，
   而 BlackBox 测试**看不到包的私有成员** —— 这暴露出脚手架里的一个真实缺陷，
   说明"凭印象写 API"确实会出错（见 D9）。
2. 既然已经证明印象不可靠，就应该**主动缩小未验证 API 的面积**：
   `StringBuilder` 的 4 个方法名 + `Double` 的 3 个方法名一共 7 个未经确认的符号，
   换成一个确定的 `+` 拼接与一个确定的插值语法。
3. 列对齐是纯装饰性的，不值得用 7 个不确定符号去换。

**取舍**：失去列对齐（`0.800` 与 `12.340` 不会右对齐），且字符串拼接是 O(n²)。
两者都只影响**展示用途**，不影响数值计算。列对齐与更高效的构建方式列入 v2
（见 ROADMAP 第 6 节）。

**推广的工程纪律**：在编译器无法验证的阶段，把不确定符号的数量当作成本来管理。

---

## D9 · 2026-10-13 · 单元测试放在 `_wbtest.mbt`（WhiteBox）

**决策**：测试文件命名为 `src/eigen_wbtest.mbt`，而不是最初设想的 `eigen_test.mbt`。

**理由**：官方 "Writing Tests" 文档明确两种测试文件的语义差异：

| 文件后缀 | 类型 | 可见性 |
|---|---|---|
| `_test.mbt` | BlackBox | 只能访问包的 **public** 成员（模拟真实用户视角） |
| `_wbtest.mbt` | WhiteBox | 可以访问包的**全部**成员 |

本项目的测试需要调用 `ffi.mbt` 里的私有 `extern "C"` 声明
（`mb_eigen_shim_probe`、`mb_eigen_matrix_*`）—— 按官方 agent skill 的建议，
extern 声明应当保持私有、只通过安全的公开 API 暴露。因此这些测试**必须**是 WhiteBox，
放在 `_test.mbt` 里会直接编译失败。

**代价与后续**：缺少 BlackBox 视角的测试（即"用户能不能正确使用这个包"）。
v2 应补一个 `eigen_test.mbt`，用包别名（预计是 `@src`）调用公开 API。
该别名需在工具链就绪后确认，已记入 PITFALLS 第 8 节。

**出处**：<https://docs.moonbitlang.com/en/latest/language/tests.html>
