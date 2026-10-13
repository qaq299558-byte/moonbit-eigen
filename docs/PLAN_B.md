# Plan B：把 C++ 胶水放到 moon 之外编译

> 本文件是**备用方案**，正常路径是 Plan A（`native-stub: ["eigen_shim.cpp"]`）。
> 什么时候需要它、怎么切、代价是什么，都在这里。
> 决策记录见 [DECISIONS.md](DECISIONS.md) D4 与 D10。

---

## 1. 何时启用

**触发条件**（对应 [ROADMAP.md](ROADMAP.md) 的熔断点，10/19 结束前必须判定）：

- `moon test --target native` 报编译 `.cpp` 失败，或
- 链接期报找不到 `mb_eigen_*` 符号，
- 且 `MOONBIT_NEW_NATIVE=0` 强制走 C 后端后仍然失败。

**先做这两件再判定**（避免误判）：

```powershell
$env:MOONBIT_NEW_NATIVE = "0"     # 强制 C 后端（新 native 后端可能不支持 stub）
moon test --target native
```

---

## 2. 为什么会有这个方案

官方把 `native-stub` 定义为 **C** stub：

> The `native-stub` field lists **C** stub source files that should be compiled
> with this package for native builds.

文档**没有**承诺 `.cpp`。而生态里唯一的 C++ 绑定先例 `illusory0x0/qpainter`
**根本没用 native-stub**，它用 `pre-build` + Makefile 把 `.cxx` 编成静态库，
再靠 `cc-link-flags` 链进来：

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

结论：**Plan B 不是野路子，而是有先例的正规做法**；只是它多维护一套构建。

---

## 3. 执行步骤

### Windows（clang-cl）

```powershell
cd D:\moonbit\moonbit-eigen
powershell -File scripts/build-shim.ps1      # 产出 build/eigen_shim.obj
# 然后按第 4 节替换 src/moon.pkg
moon test --target native
```

### Linux / macOS（g++ 或 clang++）

```bash
cd moonbit-eigen
bash scripts/build-shim.sh             # 产出 build/eigen_shim.o
# 然后按第 4 节替换 src/moon.pkg
moon test --target native
```

---

## 4. `src/moon.pkg` 的改动

### 改动前（Plan A）

```moonbit
options(
  "native-stub": [ "eigen_shim.cpp" ],
  targets: { "ffi.mbt": [ "native" ] },
  link: { "native": {
    "cc": "clang-cl",
    "stub-cc": "clang-cl",
    "cc-flags": "/std:c++17 /EHsc /bigobj /O1",
    "cc-link-flags": "",
  }},
)
```

### 改动后（Plan B，Windows）

```moonbit
options(
  // 关键：删掉 native-stub —— 胶水不再交给 moon 编译
  targets: { "ffi.mbt": [ "native" ] },
  link: { "native": {
    "cc": "clang-cl",
    // cc-flags 不再需要 C++ 语言选项（生成的 C 代码按 C 编译）
    "cc-flags": "",
    // 直接把目标文件交给链接器；Windows 下不需要额外运行库参数
    "cc-link-flags": "build/eigen_shim.obj",
  }},
)
```

### 改动后（Plan B，Linux / macOS）

```moonbit
options(
  targets: { "ffi.mbt": [ "native" ] },
  link: { "native": {
    "cc-flags": "",
    // 必须显式链 libstdc++（Windows 的 MSVC ABI 由 clang-cl 自动带走 C++ 运行时，
    // Linux 不会），这是 qpainter 配置里同样出现的一项
    "cc-link-flags": "build/eigen_shim.o -lstdc++",
  }},
)
```

---

## 5. 三个必须知道的代价（诚实记录）

### 5.1 `cc-link-flags` 里的相对路径按 pwd 解析

moon issue [#586](https://github.com/moonbitlang/moon/issues/586)：`cc-flags` /
`cc-link-flags` 是相对**进程工作目录**解析的，不是包根目录。

**含义**：必须在**模块根目录**执行 `moon build` / `moon test`。
在子目录里执行会找不到 `build/eigen_shim.obj`。
（这也是 Plan A 更稳的原因之一 —— 它完全不涉及路径。）

### 5.2 产物是平台相关的

`build/eigen_shim.obj` 是 Windows + MSVC ABI 的产物，在 Linux 上不可用；
反之亦然。这直接影响可移植性，见下一条。

### 5.3 发布成包时会退化（最重要的一条）

官方明确：**`rule` / `dev_build`（旧格式 `pre-build`）在包被下游作为依赖使用时不会执行**
（出于安全考虑，依赖不执行任意命令）。因此如果把本项目发布到 mooncakes：

- 下游用户不会触发我们的构建脚本；
- 唯一的办法是把 `build/eigen_shim.obj` **提交进仓库**；
- 而提交进仓库的 `.obj` 只对构建它的那个平台有效。

**结论**：

| | Plan A | Plan B |
|---|---|---|
| 配置复杂度 | 低 | 高（多一套构建脚本） |
| 依赖 | 未被官方承诺的行为 | 有真实先例 |
| 跨平台发布 | 天然可用 | **需要为每个平台提交一份产物，或让下游自行编译** |
| 适合 | 可发布的包 | 黑客松提交 / 单平台演示 |

**因此：Plan B 是用来"保证 10/31 交得出东西"的兜底，而不是终态。**
如果最终交付走的是 Plan B，必须在 README 的 **Limitations** 里写明
"当前为单平台预编译产物，跨平台使用需按 PLAN_B.md 重新编译"——
这属于赛事验收第 5 条要求的"说明来源与限制"。

---

## 6. 备选：编成静态库而不是直接用目标文件

如果链接器对裸 `.obj` 有意见，可以先归档成静态库再链：

```powershell
# Windows
llvm-lib /OUT:build/eigen_shim.lib build/eigen_shim.obj
# 然后 cc-link-flags: "build/eigen_shim.lib"
```

```bash
# Linux / macOS
ar rcs build/libeigen_shim.a build/eigen_shim.o
# 然后 cc-link-flags: "-Lbuild -leigen_shim -lstdc++"
```

注意 `-L` 同样受 5.1 的相对路径规则影响。

---

## 7. 切回 Plan A 的判据

如果 Plan B 能跑通、且后来发现 Plan A 其实可行（例如换个 MoonBit 版本之后），
应当切回 Plan A —— 理由是 5.3 的可移植性。
切换时把本节与 `src/moon.pkg` 的注释一并更新，并在 DECISIONS 里补一条记录。
