# MoonBit ↔ C++ 类型与内存映射表

> 本文件是本项目的核心交付物之一：它把"MoonBit 调 C++"这件事里
> 所有隐含约定写成显式契约。目标是让别人**不用重新踩一遍坑**就能写出下一个绑定。

---

## 1. 官方 ABI 对照表（基线，来自官方 FFI 文档）

| MoonBit 类型 | C ABI | 是否引用计数 |
|---|---|---|
| `Bool` / `Int` | `int32_t` | 否（unboxed） |
| `UInt` | `uint32_t` | 否 |
| `Int64` / `UInt64` | `int64_t` / `uint64_t` | 否 |
| `Float` / `Double` | `float` / `double` | 否 |
| constant `enum` | `int32_t` | 否 |
| **抽象类型 `type T`** | `void*`（必须指向合法 MoonBit 对象） | **是** |
| `#external type T` | `void*`（外部指针） | **否**（MoonBit 不做任何计数） |
| `FixedArray[Byte]` / `Bytes` | `uint8_t*` | 是 |
| `FixedArray[T]` | `T*` | 是 |
| `FuncRef[T]` | 函数指针 | 否 |

文档明确警告：**上表以外的类型没有稳定 ABI**，不要依赖其内存布局。

出处：<https://docs.moonbitlang.com/en/latest/language/ffi.html>

---

## 2. 本项目实际用到的映射

| MoonBit 侧（`src/ffi.mbt`） | C 侧（`src/eigen_shim.cpp`） | 说明 |
|---|---|---|
| `EigenMatrix`（抽象类型） | `void*` | `moonbit_make_external_object` 返回的外壳对象指针，payload 存 `MatrixBox*` |
| `FixedArray[Double]` | `double*` | 矩阵数据，**统一行主序**，逐元素搬运 |
| `Bytes` | `uint8_t*` | 错误信息（UTF-8），由 `moonbit_make_bytes` 分配 |
| `Int` | `int32_t` | 尺寸、下标、状态码、运算分派码 |
| `Double` | `double` | 元素值、范数、行列式 |

**没有用到的机制（刻意的）**：
- ❌ 没有 `FuncRef`（不需要回调）
- ❌ 没有 `Ref[T]` 出参（改用"错误哨兵 + 查询式错误信息"，见第 4 节）
- ❌ 没有字符串参数入参（数值库不需要）
- ❌ 没有 `#external type`（我们的句柄必须走 GC finalizer）

---

## 3. 内存与所有权契约

### 3.1 C++ 对象的生命周期

```
MoonBit 引用计数到 0
        ↓
MoonBit 运行时回收外壳对象
        ↓
调用 finalize(self)          ← 我们在 shim 里注册的 matrix_finalize
        ↓
delete *(MatrixBox**)self    ← 只释放 payload 里的 C++ 对象
```

三条硬规则：

1. **finalize 不得释放 `self` 本身** —— 那是运行时的职责，自己释放会双重释放。
2. 返回给 MoonBit 的必须是**外壳对象**的指针，不是 `MatrixBox*`。直接用 `MatrixBox*`
   会让 MoonBit 的引用计数作用在错误的地址上。
3. MoonBit 侧必须绑到**抽象类型**（`type EigenMatrix`），
   **不能**用 `#external` —— 否则 finalizer 永远不会跑，C++ 对象全部泄漏。

### 3.2 参数的引用计数契约

本项目的所有非原始类型参数都标了 `#borrow`：

```moonbit
#borrow(data)
extern "C" fn mb_eigen_matrix_from_array(...) -> EigenMatrix = "..."
```

含义：**shim 只在调用期间读取/写入该参数，绝不保存指针**。
因为不保存，所以不需要 `moonbit_decref`，也不会出现 GC 回收后 C 侧拿到悬垂引用。

⚠️ **反面情形**：如果哪天要让 C++ 侧长期持有 MoonBit 对象（例如回调注册），
**必须去掉 `#borrow`**，按 owned 约定处理，并在 C 侧需要长期持有时 `moonbit_incref`。

### 3.3 返回值的方向

| 方向 | 做法 |
|---|---|
| C++ → MoonBit（矩阵） | `moonbit_make_external_object` 包一层，带 finalizer |
| C++ → MoonBit（字符串） | `moonbit_make_bytes` + `memcpy`，MoonBit 侧 `@utf8.decode_lossy` |
| MoonBit → C++（数组） | 直接传 `FixedArray[Double]`，`#borrow` |
| MoonBit → C++（尺寸/标量） | 直接传 `Int` / `Double`（unboxed，无需管理） |

**关于字符串为什么不用 `moonbit_string_t`**：
官方黑板报文章用的是 `moonbit_make_string`，但该符号在官方文档、
官方 agent skill、issue 中均查不到出处。官方 agent skill 推荐的是
`moonbit_make_bytes` + MoonBit 侧解码，因此本项目采用后者。
好处是 C++ 侧完全不需要处理 UTF-16，中文自然可用。

---

## 4. 错误传递契约

跨语言边界的错误处理有两种常见做法，各自的问题：

| 做法 | 问题 |
|---|---|
| 返回 `nullptr` 表示失败 | MoonBit 侧把返回值绑到**抽象类型**，抽象类型没有 null 语义；拿到垃圾句柄会崩溃 |
| 返回负状态码 + 出参 | 需要 `Ref[T]` 出参，多一层未验证机制 |

**本项目采用第三种：错误哨兵 + 查询式错误信息。**

1. 每个返回句柄的 C 函数**永远返回一个真实的外壳对象**，绝不返回 `nullptr`
   （唯一例外是极端 OOM，此时返回 `nullptr`，MoonBit 侧需容错）。
2. 失败时返回的盒子 `valid == false`。
3. MoonBit 侧通过 `mb_eigen_matrix_rows()` 判断：
   - `>= 0` → 有效，值为行数
   - `-1` → **无效 / 上一次操作失败**
4. 错误原因通过 `mb_eigen_last_error() -> Bytes` 获取（成功时为空）。
5. 所有 C++ 异常在 shim 内部被 try/catch 捕获，转成"哨兵 + 错误信息"，
   **异常绝不跨越 ABI 边界**（跨语言传播 C++ 异常是未定义行为）。

MoonBit 侧把这一切收敛成 `Result[T, String]`，用户永远看不到状态码。

```
C 侧                          MoonBit 侧
─────────────────────────────────────────────────
valid=false, rows()==-1  ──▶  Err(last_error())
正常矩阵, rows()>=0       ──▶  Ok(matrix)
```

---

## 5. 与官方教程做法的差异（以及为什么）

| 主题 | 官方黑板报教程 | 本项目 | 原因 |
|---|---|---|---|
| 字符串返回 | `moonbit_make_string` 构造 `moonbit_string_t` | `moonbit_make_bytes` + `@utf8.decode_lossy` | 前者符号无官方出处；后者是官方 agent skill 推荐做法 |
| 字符串入参 | MoonBit 侧转 `Bytes`（手工补 `\0`） | 数值库不需要字符串入参 | 范围不同 |
| 外部类型 | `#extern type`（不透明句柄，无 finalizer） | 抽象类型 + `moonbit_make_external_object` | 官方明确要求：带 finalizer 的对象必须绑抽象类型 |
| 错误处理 | 返回状态码 | 错误哨兵 + `Result` | 避免抽象类型上的 null 语义问题 |
| 属性写法 | `#extern`（2025-08 文章） | `#external`（现行文档） | 官方现行文档用 `#external` |
| `#borrow` | 部分位置使用 | 所有非原始类型参数都标 | 官方已声明默认语义正迁移到 `#borrow` |

---

## 6. 构建期配置速查

```moonbit
// src/moon.pkg
options(
  "native-stub": [ "eigen_shim.cpp" ],   // ⚠️ 官方只承诺 C；.cpp 需实测（Plan A）
  targets: { "ffi.mbt": [ "native" ] },  // 不要用 supported-targets: ["native"]
  link: { "native": {
    "cc": "clang-cl",                    // Windows 只能是 cl.exe / clang-cl.exe
    "stub-cc": "clang-cl",               // 必须与 cc 一致
    "cc-flags": "/std:c++17 /EHsc /bigobj /O1",  // 不放任何路径（issue #586）
    "cc-link-flags": "",                 // Linux/CI 需改 "-lstdc++"
  }},
)
```

关键点：
- **cc-flags 里不放 `-I` 路径** —— issue #586 说明它按 pwd 解析；相对包含更稳。
- **不用 `supported-targets: ["native"]`** —— 官方 skill 明确劝阻，会限制下游包。
- **`cc` 与 `stub-cc` 必须一致** —— 官方文档"强烈建议"。

---

## 7. 参考

- 官方 FFI 文档（类型表、Lifetime management、`#borrow`）：<https://docs.moonbitlang.com/en/latest/language/ffi.html>
- 官方包配置（`native-stub` / `link.native.*` / Windows 工具链要求）：<https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html>
- 官方黑板报 C-FFI 教程：<https://moonbitlang.cn/pearls/moonbit-cffi>
- 官方 agent skill（C 绑定的推荐流程与 `moonbit.h` API 表）：<https://github.com/moonbitlang/skills/tree/master/skills/moonbit-c-binding>
- 本项目踩坑记录：见 [PITFALLS.md](PITFALLS.md)
