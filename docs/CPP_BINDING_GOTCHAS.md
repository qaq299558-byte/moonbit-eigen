# 写给 MoonBit 社区：接 C++ 库时踩过的 12 个坑

> 本文全部内容来自 [moonbit-eigen](../README.md)（把 Eigen 接入 MoonBit）的实测过程。
> **每条都是真踩过、有报错原文、并最终验证通过的**，不是从文档整理的清单。
> 每条按「现象 → 原因 → 做法」写，可以直接抄。
>
> 验证环境：`moon 0.1.20261012` / `moonc v0.10.15`，Windows + VS Build Tools 18（MSVC 14.51），
> Windows PowerShell 5.1。版本不同处请以你本机为准。

---

## A. 配置与构建

### 1. `moon.pkg` 是**按包**配置的 —— 改 A 却跑 B 不会报错

**现象**：改了 `src/moon.pkg` 的编译选项，跑 `moon test --target native selftest`，
选项像是"没生效"。我因此连续得出三个错误结论，绕了大半天。

**原因**：`selftest` 包的 stub 用的是 **`selftest/moon.pkg`** 的配置。
`src/moon.pkg` 根本没参与那次构建 —— 而 moon **不会**告诉你这件事。

**做法**：

- 验证配置类改动时，**确认"改的包"与"跑的包"是同一个**；
- 最快的自检：**故意写一个非法值，看它是否真的报错**。
  没报错就说明这段配置压根没被读到。

```powershell
# 例：往 stub-cc-flags 塞一个不存在的 flag
# 若构建照样成功 → 你改的不是这次构建用的那个 moon.pkg
```

> 这条排第一，因为它的代价最大：**它会让你得到关于工具链的错误结论。**

### 2. 声明了 `native-stub` 的**库包**必须按包名调用

**现象**：

```
libcmt.lib(exe_main.obj) : error LNK2019: 无法解析的外部符号 main
...\src.exe : fatal error LNK1120: 1 个无法解析的外部命令
```

**原因**：整模块执行 `moon build/test --target native` 时，
**声明了 `native-stub` 的库包会被额外尝试链接成 `.exe`**，
而库包没有 `main`。用对照实验定位：新建一个**没有 stub** 的纯库包，
`moon build` 完全正常 → 触发条件是 `native-stub`，与 `pkgtype` 无关
（显式写 `pkgtype(kind: "library")` 也无效）。

**做法**：**调用时带包名** —— 只走 test 目标，不碰那条路径。

```bash
moon test --target native src        # ✅
moon test --target native selftest   # ✅
moon test --target native           # ❌
```

### 3. `cc-flags` 与 `stub-cc-flags` 语义完全不同

| 字段 | 语义 | 作用范围 |
|---|---|---|
| `cc-flags` | **替换**默认值 | **所有**源文件（含 moonc 生成的 C） |
| `stub-cc-flags` | **追加**到默认值之后 | 只有 stub |

**两个推论，都踩过：**

**(a) 别往这两个字段里写 `/std:`。** moon 给 stub 的默认命令行**已经带了 `/std:c11`**：

```
cl /Fo...obj /I<moon include> /Z7 /c /std:c11 /nologo <stub.cpp> <本字段> /MT
```

再加一个 `/std:c++17` 就是两个 `/std:` 并存：

```
cl: 命令行 error D8016: "/std:c11" 和 "/std:c++17" 命令行选项不兼容
```

正确做法是**不指定标准版本**，让 cl 按扩展名自己选（`.c` 走 C，`.cpp` 走默认的 C++14）。

**(b) `cc-flags` 是替换而不是追加。** 想靠它加一个选项，
可能顺手把 moon 的默认选项全弄丢了。**能用 `stub-cc-flags` 就别用 `cc-flags`。**

> 合法用法举例：`cc-link-flags` 是给链接阶段的，与上面两个不冲突。

### 4. Windows 上「找不到 cl.exe」通常是误报

**现象**：自己写的检测脚本报 `未找到 cl.exe 或 clang-cl.exe`，但实际上能正常构建。

**原因**：**moon 是通过 `vswhere` 发现 MSVC 的**，
而装好的 VS Build Tools **不会**把 `cl.exe` 放进 `PATH`。
只查 `PATH` 必然误判。

**做法**：别只查 PATH，用 `vswhere`：

```powershell
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installs = & $vswhere -products * `
  -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  -property installationPath
```

**顺带两条**：

- **不要硬编码 `cc` / `stub-cc`**，让 moon 自己发现工具链。
  硬编码 `clang-cl` 会让"装了 MSVC 但没装 LLVM"的机器直接失败，
  而且会禁用 debug 构建的 TCC 加速。
- Windows 上 native 后端**只接受 MSVC 兼容工具链**，官方明确排除 MinGW。

---

## B. FFI 边界

### 5. `moonbit_make_external_object` 返回的是 **payload 指针**，取值必须解引用

**现象**：FFI 调用不崩溃，但 `rows()` 返回 `607`（期望 `2`），随后进程崩溃。

**原因**：`moonbit_make_external_object(finalize, size)` 返回的是
**指向 payload 的指针**，不是容器地址。存进去再取出来时必须解引用：

```cpp
// ❌ 漏掉解引用：拿到的是 payload 首地址，当成结构体指针用 → 读到垃圾
static Box *unwrap(moonbit_object_t h) { return static_cast<Box *>(h); }

// ✅
static Box *unwrap(moonbit_object_t h) { return *static_cast<Box **>(h); }
```

**做法**：写一个 `wrap()` / `unwrap()` 配对，**所有** FFI 出入口只走这两个函数。
另外注意：finalizer **不要**去 free 容器本身，运行时负责它。

> 这个 bug 是"零第三方依赖的最小 FFI 自检包"第一次运行就抓到的 ——
> **把机制验证和业务逻辑解耦**，是这次最值的一个决定。

### 6. 指针参数必须标注 `#borrow` / `#owned`

**现象**：所有指针参数都没标注时，一次性报 19 个：

```
error 55: unannotated_ffi
```

**原因**：MoonBit 要求显式声明跨边界的**所有权语义**。
而且默认是 `#owned`（会加引用计数），对"只是借用一下"的句柄来说，
**不标注不只是编译报错，还有真实的引用计数风险**。

**做法**：注解写在 **`extern` 声明的上一行**（不是行尾 —— 这点很容易写错），
一个参数或多个参数都行：

```moonbit
///|
extern "C" fn mb_eigen_matrix_rows(m : EigenMatrix) -> Int32 = "mb_eigen_matrix_rows"

///|
/// data 是 FixedArray[Double]（C ABI: double*）。
#borrow(data)
extern "C" fn mb_eigen_matrix_from_array(
  rows : Int32,
  cols : Int32,
  data : FixedArray[Double],
  len : Int32,
) -> EigenMatrix = "mb_eigen_matrix_from_array"

///|
#borrow(handle, out)
extern "C" fn mb_eigen_matrix_copy_to(handle : EigenMatrix, out : FixedArray[Double]) -> Int32 = "..."
```

**怎么选 `#borrow` 还是 `#owned`**：看你的胶水层会不会**保存**这个指针。

- 只做"调用期间读取/写入"，从不存进长生命周期的结构 → **`#borrow`**（本项目全部如此，
  这个判断是可验证的：`grep` 一遍胶水层，没有任何一处把参数存下来）；
- 需要把指针留在 C 侧 → `#owned`，并自己管好引用计数。

**顺带**：`FixedArray[Double]` → `double*`、`Bytes` → `uint8_t*`；
导出给 C 用的函数要有 `MOONBIT_FFI_EXPORT`（Windows 上即 `__declspec(dllexport)`）。

### 7. `/utf-8` 不能省 —— 否则中文错误信息会变乱码

**现象**：C++ 侧写的中文错误信息，到 MoonBit 侧显示成乱码。

**原因**：中文 Windows 上 MSVC 默认按**系统代码页（GBK）**解释源文件，
于是中文字面量以 GBK 字节进入程序，而 MoonBit 侧按 UTF-8 解码 —— 两头不一致。

**做法**：MSVC 加 `/utf-8`；GCC/Clang 默认就是 UTF-8，无需处理。

```
"stub-cc-flags": "/EHsc /utf-8 /bigobj /O1"
```

| 选项 | 为什么需要 |
|---|---|
| `/EHsc` | 开启标准 C++ 异常展开语义（Eigen 断言与 `std::exception` 需要） |
| `/utf-8` | 源文件与执行字符集都按 UTF-8 |
| `/bigobj` | 重度模板库（Eigen 之类）会展开出大量 COMDAT 段 |
| `/O1` | 压低优化级别以控制模板编译时间 |

### 8. 字符串跨边界：`moonbit_make_bytes` + `@utf8.decode_lossy`

**别把 MoonBit 的 `String` 当 `char*` 用** —— 它是 GC 管理的 UTF-16 对象。
官方推荐的边界做法是**只传字节**：C 侧 `moonbit_make_bytes` + `memcpy`，
MoonBit 侧 `@utf8.decode_lossy`。

```cpp
// C++ 侧：把 std::string 以 UTF-8 字节送出去
// 注意 moonbit_make_bytes 的签名是 (长度, 初始值)，不是 (指针, 长度) —— 别想当然。
moonbit_bytes_t to_mbt_bytes(const char *s) {
  const std::size_t n = s == nullptr ? 0 : std::strlen(s);
  moonbit_bytes_t out = moonbit_make_bytes(static_cast<std::int32_t>(n), 0);
  if (n > 0) {
    std::memcpy(out, s, n);
  }
  return out;
}
```

```moonbit
// MoonBit 侧：解码。注意参数类型是 BytesView，要切片
fn last_error() -> String {
  @utf8.decode_lossy(mb_eigen_last_error()[:])
}
```

**两个细节**：

- `@utf8.decode_lossy` 的参数是 **`BytesView`**，所以要写 `bytes[:]`，直接传 `Bytes` 会类型不匹配；
- 包 `moonbitlang/core/encoding/utf8` 要显式 import，`builtin` 也要
  （否则触发 `core_package_not_imported` 警告）。

---

## C. 跨语言正确性

### 9. 参数校验不能想当然：Eigen 的断言是**进程级崩溃**，不是可捕获异常

**现象**：测试跑起来后直接崩：

```
Assertion failed: aLhs.rows() == aRhs.rows() && aLhs.cols() == aRhs.cols(),
file .../Eigen/src/Core/CwiseBinaryOp.h, line 110
测试进程退出码 0xc0000409
```

**原因**：我的 `dot` 只检查了"元素个数相同"，就用 `cwiseProduct(b).sum()` 实现。
但 **Eigen 的逐元素二元运算断言的是"形状完全相同"**，
而 `1×3` 与 `3×1` 元素个数相同、形状不同 → 断言触发。

**关键认知**：这类断言**不是 C++ 异常**，`try/catch` 兜不住，
它就是 `abort()` —— 在 FFI 场景下，你的宿主语言进程会一起死。

**做法**：

- 在**自己的胶水层**把校验做完整，别指望底层库的断言给你兜底；
- 用**手工遍历**代替不确定语义的库函数（这里改成按存储顺序逐元素求和）；
- 把契约写进注释，并**为契约本身补一条测试**（`2×3` 与 `3×2` 必须返回 `Err` 而不是崩溃）。

> **教训**：`size()` 相等 ≠ 形状相容。跨语言边界上的每个前置条件，
> 都值得你自己显式检查一遍 —— 因为对面那个库的"检查"可能是直接终止进程。

### 10. 存储布局的隐含约定要**显式归一化**

**现象**：绑定结果和纯 MoonBit 实现对不上（或悄悄错位）。

**原因**：Eigen 默认**列主序**（column-major），而 MoonBit 的数组直觉是行主序。
这种差异**不会报错**，只会算错。

**做法**：**所有跨边界的数据搬运都按 `(i, j)` 逐元素进行**，
对外统一行主序，不让存储布局这种隐含约定泄漏到用户侧。

代价是握手时多一点拷贝 —— 但换来的是**不会算错**。
并且**写一份对拍测试**：用独立的纯 MoonBit 三重循环实现校验绑定的结果。

```
最大绝对误差 = 0
对拍通过：绑定的数据搬运与乘法结果与纯 MoonBit 实现一致。
```

> 这种"独立实现对拍"是跨语言项目里性价比最高的测试：
> 它同时能抓住**存储布局错误**和**数值搬运错误**，
> 而且参考实现不依赖任何第三方库，谁都能跑。

---

## D. 验证与可信度

### 11. ASan 会「假绿」—— 必须断言插桩真的生效

**没生效却报告成功，比没有 ASan 更危险。** 我实际踩到两种形式：

**形式一：脚本注入了一个不存在的字段。**
脚本用正则替换 `cc-flags` / `cc-link-flags`，但本仓库**刻意没有设置这两个字段**
（留给 moon 自动发现工具链）→ 替换**静默失败**，
脚本照样打印"sanitizer 运行结束（无输出即无问题）"。

**形式二：测试通过，但产物里没有插桩。**

**做法**：三道断言，缺一不可。

```
字段必须存在  →  注入必须真的改到文件  →  产物里必须真的出现 ASan 符号
```

```powershell
# 最后一关：去产物字节里找证据
$txt = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($exe))
if (-not ($txt.Contains('clang_rt.asan') -or $txt.Contains('__asan'))) {
  throw "测试通过了但没有 ASan 痕迹 —— 假绿，本次运行不能作为内存安全证据"
}
```

**Windows/MSVC 的完整配方**（已实测，18/18 在 ASan 生效下通过）：

1. 往 `stub-cc-flags` 加 `/fsanitize=address`；
2. **把 ASan 运行时 DLL 所在目录放进 `PATH`**；
3. （可选）`cc-link-flags` 加 `/DEBUG`，让报告带行列号。

**两个反直觉点：**

| 现象 | 真相 |
|---|---|
| 测试进程退出码 **`0xc0000135`** | **不是测试失败**，是找不到 `clang_rt.asan_dynamic-x86_64.dll`。它就在 `cl.exe` 自己的目录下（`<VS>\VC\Tools\MSVC\<版本>\bin\Hostx64\x64\`）—— 所以从 "Developer Command Prompt" 里跑就没问题，普通终端里跑就撞上 |
| 把 `/fsanitize=address` 放进 `cc-link-flags` | 会让 `link.exe` 报 `LNK4044: 无法识别的选项`；插桩后的 `.obj` 自带 `clang_rt.asan` 的 default-lib 指令，**不需要**加 |

> 关于范围：只插桩 C++ 胶水层就够了。要连 moonc 生成的 C 一起插桩得改
> `cc-flags`，而它会**替换**全部默认选项，风险大收益小 ——
> 真正有风险的代码是你写的那层胶水。

### 12. PowerShell 5.1 的三连坑（写构建脚本必踩）

如果你在 Windows 上写辅助脚本（大概率会），这三条**一定会遇到**：

**(a) 含中文的 `.ps1` 必须存成 UTF-8 **with BOM**。**

```powershell
# 无 BOM 时，5.1 按系统 ANSI（中文 Windows 上是 GBK）解码，
# 中文全变乱码，某些字节序列还会把字符串引号"吃掉"：
#   语句块或类型定义中缺少右"}"。
#   字符串缺少终止符: "。
# 报错位置看起来毫无道理 —— 因为真正的问题是编码。
```

> PowerShell 7 默认按 UTF-8 读、不依赖 BOM，所以**在 7 上测不出来**。
> 跨版本的脚本要用最保守的那个版本的规则去验证。

**(b) `Join-Path` 的三参数形式是 PS 6+ 才有的。**

```powershell
Join-Path $a "b" "c"                    # ❌ 5.1: 找不到接受实际参数"c"的位置形式参数
Join-Path (Join-Path $a "b") "c"        # ✅
```

**(c) 原生命令写 stderr + `$ErrorActionPreference = 'Stop'` = 终止性错误。**

```powershell
# 5.1 下把原生命令的 stderr 用 2>&1 接进管道会产生 NativeCommandError；
# 脚本开头若设了 Stop，它就成了**终止性错误**，
# 脚本会崩在"判读 $LASTEXITCODE"之前。
# 而"正常输出走 stderr"的程序很多：git 的进度、moon 的 warning、cl 的版权横幅。
```

```powershell
# 修法一：临时切回 Continue，以 $LASTEXITCODE 为唯一判据
$saved = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$output = Invoke-Expression $cmd 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = $saved

# 修法二（编译器场景更好）：让 cmd.exe 自己重定向，PowerShell 完全看不到 stderr
& cmd.exe /c "$Cc $clArgs > `"$tmpLog`" 2>&1"
```

**附带一条**：**自然结束的脚本不保证返回 0。**
实测某脚本走到成功分支、打印完"完成"后自然结束，
`powershell -File` 返回的是 **-1**；补上显式 `exit 0` 才正确。

---

## 附：两条不属于语言、但同样值钱的教训

**1. 挑第三方源必须验证内容，不能只看名字。**
我按名字选了 `gitee.com/mirrors/eigen`，结果它**根本不是同一个项目**
（那是 Artsy 的 iOS 应用）。现在的做法是：拿到源码后**校验关键文件存在**
（`Eigen/Dense`），并**解析版本宏打印真实版本号**写进 `SOURCE.txt`。

**2. 文档里写 A、实际是 B，是最容易穿帮的错。**
我们一开始按计划写"使用 Eigen 3.4.0"，实际拿到的是 **3.3.90**
（镜像的 master 是 3.4 正式发布前的开发版本号）。
现在脚本会**读出真实版本并打印**，文档也只写实测值。

> 这类问题不会让代码挂掉，但会让评审对你的所有数字失去信任。

---

## 一页速查

| # | 坑 | 一句话 |
|---|---|---|
| 1 | moon.pkg 按包配置 | 改 A 跑 B 不报错；用非法值自检 |
| 2 | native-stub 库包 | 必须按包名调用，否则 `LNK2019: main` |
| 3 | cc-flags vs stub-cc-flags | 前者替换+全局，后者追加+仅 stub；都别写 `/std:` |
| 4 | cl.exe 不在 PATH | 用 `vswhere`，别用 `Get-Command` |
| 5 | external_object 返回值 | 是 payload 指针，取值必须解引用 |
| 6 | 指针参数 | 必须标 `#borrow` / `#owned` |
| 7 | `/utf-8` | 中文 Windows 上不能省 |
| 8 | 字符串 | `moonbit_make_bytes` + `@utf8.decode_lossy(bytes[:])` |
| 9 | 库断言 | 可能是 `abort()`，`try/catch` 兜不住 → 自己校验 |
| 10 | 存储布局 | 显式归一化 + 与独立实现写对拍测试 |
| 11 | ASan 假绿 | 必须断言产物里有 `__asan` |
| 12 | PowerShell 5.1 | BOM / Join-Path / stderr / 显式 exit 0 |

---

*本文来自 [moonbit-eigen](../README.md) 的实现过程。相关细节见
[PITFALLS.md](PITFALLS.md)（逐条踩坑记录）、
[TYPE_MAP.md](TYPE_MAP.md)（类型与内存映射表）、
[SCRIPTS.md](SCRIPTS.md)（构建脚本说明）。*
