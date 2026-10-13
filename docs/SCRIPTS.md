# 脚本说明（scripts/）

> **为什么有这个文件**：脚本头部原本写着大段"为什么这么做"的注释，
> 与 [PITFALLS.md](PITFALLS.md) 严重重复，而且中文注释在 UTF-8 下
> 每字符占 3 字节，导致仓库的语言统计被 PowerShell 主导。
> 现在**理由集中在本文件，脚本本身保持精简** —— 一处维护，两边都不吃亏。

所有脚本都按"脚本所在目录的上一级"定位仓库根目录，
因此**从任何工作目录调用都行**。

---

## 平台与依赖速查

| 脚本 | 平台 | 作用 | 实测状态 |
|---|---|---|---|
| `fetch-eigen.ps1` | Windows | 获取 Eigen 源码 | ✅ 已实测 |
| `fetch-eigen.sh` | Linux/macOS | 获取 Eigen 源码 | ⚠️ 未在开发机验证 |
| `demo.ps1` | Windows | 环境自检 + 一键复现演示（8 步） | ✅ 已实测全绿 |
| `demo.sh` | Linux/macOS | 一键复现演示 | ⚠️ 未在开发机验证 |
| `run-asan.ps1` | Windows | ASan 内存检查 | ✅ 已实测生效 |
| `run-asan.sh` | Linux/macOS | ASan 内存检查（GCC 语法） | ⚠️ 未在开发机验证 |
| `build-shim.ps1` | Windows | Plan B：预编译 C++ 胶水 | ✅ 已实测 |
| `build-shim.sh` | Linux/macOS | Plan B：预编译 C++ 胶水 | ⚠️ 未在开发机验证 |

**为什么 Windows 脚本写得更多**：本项目的 native 目标在 Windows 上要求
MSVC 兼容工具链，开发与验证也都在该平台上完成，因此 Windows 侧是经过
实跑验证的一等公民；Linux 侧脚本按同一思路编写但未经本机验证，故如实标注。

---

## 1. 获取 Eigen：`fetch-eigen.ps1` / `.sh`

Eigen **不入库**（`src/third_party/` 在 `.gitignore` 里）。理由：
数百个第三方文件会让仓库体积与审查负担陡增，而"按固定版本 + 可重复脚本"
同样能保证 CI 与本地拿到同一份代码。

**三条路径，任一条成功即可：**

| 路径 | 方式 | 适用网络 |
|---|---|---|
| A | `git clone` GitLab 官方 tag | CI / 非受限网络（官方源） |
| B | `git clone` GitHub 镜像 `libigl/eigen` 的 master | ★ 受限网络下最可能成功 |
| C | GitHub 指定 commit 的源码归档 zip（普通 HTTPS） | git 被封但 HTTPS 通时 |

> **选源必须验证内容，不能只看名字。** 踩坑实录见
> [PITFALLS 第 10.4 节](PITFALLS.md)：`gitee.com/mirrors/eigen`
> 根本不是同一个项目（那是 Artsy 的 iOS 应用）。

成功后脚本会：
1. 校验 `Eigen/Dense` 存在；
2. **读出真实版本号并打印**（解析 `Macros.h`，不假设）；
3. 写 `src/third_party/eigen/SOURCE.txt` 记录来源、锁定方式、实际版本 ——
   这是可复现性的凭证。

> ⚠️ **实际拿到的是 Eigen 3.3.90，不是 3.4.0**。原因与影响见
> [PITFALLS 第 10.3 节](PITFALLS.md)。

---

## 2. 环境自检：已并入 `demo.ps1`

6 个步骤，用来回答"这台机器到底能不能跑这个项目"：

```
[1/6] 工具链      moon 版本 + MSVC（经 vswhere）
[2/6] moon check  纯类型检查
[3/6] selftest    FFI 机制判定 —— Plan A 是否成立的结论在这里出来
[4/6] Eigen       按固定版本获取
[5/6] 完整测试    含 Eigen 绑定的 18 个测试
[6/6] 结论
```

**设计要点：**

- **MSVC 检测必须用 `vswhere`，不能只查 PATH。**
  moon 自己是用 `vswhere` 发现 MSVC 的，装好的 VS Build Tools
  **不会**把 `cl.exe` 放进 PATH。只查 PATH 会误报"未找到编译器"。
- **Step 3 失败会重试一次。** Windows 上刚构建出的 `.exe` 偶发被杀软
  扫描暂锁，moon 报 `Failed to spawn command` —— 这不是测试失败，
  更不意味着 Plan A 不成立。

---

## 3. 一键复现演示：`demo.ps1` / `demo.sh`

按顺序跑完"类型检查 → 测试 → 三个示例"，输出同时落盘到 `demo/out/`，
可直接作为验收附件。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\demo.ps1
```

**`Run()` 里那段 `ErrorActionPreference` 切换不能删** —— 原因见
[PITFALLS 第 11 节](PITFALLS.md)：5.1 下原生命令写 stderr + `Stop`
会变成终止性错误，而 `moon check` 恰好会往 stderr 写一条 warning。

---

## 4. 内存检查：`run-asan.ps1` / `run-asan.sh`

跨语言边界的所有权类 bug（悬垂引用、双重释放、越界写）大多
"运行时才炸、且不炸在出错点"，所以 ASan 越早接越好。

**Windows/MSVC 的配方（已实测）：**

1. 往 `src/moon.pkg` 的 `stub-cc-flags` 加 `/fsanitize=address`；
2. **把 ASan 运行时 DLL 所在目录放进 PATH**；
3. 可选：`cc-link-flags` 加 `/DEBUG`。

**两个不看清楚就会得出错误结论的地方：**

| 现象 | 真相 |
|---|---|
| 测试进程退出码 `0xc0000135` | 不是测试失败，是找不到 `clang_rt.asan_dynamic-x86_64.dll`（它就在 cl.exe 自己目录下） |
| 把 `/fsanitize=address` 放进 `cc-link-flags` | 会让 link.exe 报 `LNK4044` 无法识别；插桩后的 `.obj` 自带 default-lib 指令，**不需要**加 |

**三道防"假绿"断言**（这是本脚本最重要的部分）：

```
字段必须存在  →  注入必须真的改到文件  →  产物里必须真的出现 ASan 符号
```

**没生效却报告成功，比没有 ASan 更危险。** 本脚本的前一版正是如此：
它用正则替换 `cc-flags` / `cc-link-flags`，而这两个字段在本仓库里
**刻意没有设置**（留给 moon 自动发现工具链），替换静默失败却报告
"sanitizer 运行结束（无输出即无问题）"。完整分析见
[PITFALLS 第 12 节](PITFALLS.md)。

**范围说明**：只插桩 C++ 胶水层。MoonBit 生成的 C 代码要插桩需改
`cc-flags`，而 `cc-flags` 会**替换** moon 的全部默认编译选项，
风险大收益小 —— 本项目真正的风险代码是 FFI 边界上的那层 C++ 胶水。

---

## 5. Plan B：`build-shim.ps1` / `build-shim.sh`

**正常情况下不需要它。** Plan A（把 `.cpp` 直接作为 `native-stub`）
已在 2026-10-13 实测成立，整套绑定都跑通了。

它存在的意义是"如果官方对 `.cpp` 作 stub 的支持发生变化"时的退路：
在 moon 之外先把 C++ 编成目标文件，再用 `cc-link-flags` 链进来
（生态先例 `illusory0x0/qpainter` 走的就是这条路）。

**修过的三个错误**（早期版本跑不起来）：

| 问题 | 后果 |
|---|---|
| 默认 `-Cc clang-cl` | 本机没装 LLVM，但 MSVC 已装 → 误报"未找到编译器" |
| 用 `Get-Command cl` | cl **不在 PATH 上** → 同上 |
| 缺 `/utf-8` | `eigen_shim.cpp` 里有中文，错误信息会变乱码 |
| 直接用 cl 不经 vcvars | 找不到标准库头文件 |

现在它用 `vswhere` 定位 VS、经 `vcvars64.bat` 初始化环境后再调用 `cl`。

---

## 6. 跨脚本的通用约定

| 约定 | 原因 |
|---|---|
| `.ps1` 必须存成 **UTF-8 with BOM** | 5.1 读无 BOM 文件时按系统 ANSI（GBK）解码，中文会破坏解析 —— [PITFALLS 9.5](PITFALLS.md) |
| 不写三参数 `Join-Path $a "b" "c"` | 那是 PS 6+ 语法 —— [PITFALLS 9.6](PITFALLS.md) |
| 原生命令的 stderr 不当错误判据 | 见上面第 3 节 —— [PITFALLS 11](PITFALLS.md) |
| 成功分支末尾写显式 `exit 0` | 自然结束的脚本**不保证**返回 0（实测返回 -1） |
| 用 `$LASTEXITCODE` 而非 `$?` | 原生命令的成功与否只有退出码说了算 |

**改完 `.ps1` 之后务必确认首三字节是 `EF BB BF`** —— 某些编辑工具会把 BOM 写掉。

```powershell
$b = [System.IO.File]::ReadAllBytes('scripts\fetch-eigen.ps1')
"{0:X2} {1:X2} {2:X2}" -f $b[0], $b[1], $b[2]   # 应为 EF BB BF
```

---

## 7. 关于 moon 是按包配置的（重要）

`moon` 的编译选项写在**每个包自己的 `moon.pkg`** 里。
**改 `A/moon.pkg` 却跑 `moon test B`，不会报错**，
只会安静地按 B 的配置构建 —— 于是你会得出关于 A 的错误结论。

实测代价：摸 ASan 配方时因此绕了很大弯路，见
[PITFALLS 第 12.4 节](PITFALLS.md)。

另外，声明了 `native-stub` 的**库包**必须**按包名调用**：

```powershell
moon test --target native src        # ✅
moon test --target native selftest   # ✅
moon test --target native            # ❌ 会给库包也尝试链接 .exe → LNK2019: main
```
