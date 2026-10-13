// selftest/smoke_wbtest.mbt —— FFI 机制自检的单元测试
//
// 这些测试的定位很特殊：它们**不是**在测"功能对不对"，
// 而是在测"机制能不能用"。任意一条失败，都意味着 Plan A 有麻烦。
//
// WhiteBox（_wbtest.mbt）而不是 BlackBox：因为要直接调用
// smoke_ffi.mbt 里的私有 extern 声明（mb_smoke_probe 等）。
//
// ⚠️ 本包的测试需要 C++ 工具链才能真正运行（moon test --target native）。
//    类型检查（moon check）不需要。

///|
fn assert_close(actual : Double, expected : Double, tol : Double) -> Unit {
  let diff = if actual > expected {
    actual - expected
  } else {
    expected - actual
  }
  if diff > tol {
    abort("期望 \{expected}，实际 \{actual}")
  }
}

///|
fn make(rows : Int32, cols : Int32) -> Smoke {
  match Smoke::create(rows, cols) {
    Ok(m) => m
    Err(msg) => abort("创建失败: \{msg}")
  }
}

// ── 机制 1：extern "C" + MOONBIT_FFI_EXPORT 是否真的进入构建 ──────────────

test "probe：C++ 胶水被当作 C++17 编译并链接进来" {
  // C++17 → 17000 + 16 = 17016
  let p = mb_smoke_probe()
  if p < 17000 {
    abort("probe 返回 \{p}，说明 C++ 源文件没有以 C++17 编入构建")
  }
}

// ── 机制 2：moonbit_make_external_object + finalizer + 抽象类型 ────────────

test "外部对象句柄可用，字段读写正常" {
  let m = make(2, 3)
  if m.rows() != 2 {
    abort("rows() 返回 \{m.rows()}，期望 2")
  }
}

test "外部对象可安全大量创建（压力 GC，检验 finalizer 路径不崩）" {
  // 刻意创建很多对象并让它们立刻不可达。
  // 若引用计数/finalizer 的约定用错（例如该 #borrow 却按 owned 处理），
  // 这里最容易崩或泄漏。
  for i = 0; i < 500; i = i + 1 {
    let m = make(4, 4)
    if m.rows() != 4 {
      abort("第 \{i} 次创建的 rows() 异常")
    }
  }
}

// ── 机制 3：#borrow 传参 + 数据写入 ──────────────────────────────────────

test "写入与求和正确（验证 #borrow 传参没有踩内存）" {
  let m = make(2, 2)
  let values : Array[Double] = [1.0, 2.0, 3.0, 4.0]
  for k = 0; k < 4; k = k + 1 {
    let i = k / 2
    let j = k % 2
    match m.set(i, j, values[k]) {
      Ok(_) => ()
      Err(msg) => abort("写入 (\{i},\{j}) 失败: \{msg}")
    }
  }
  assert_close(m.sum(), 10.0, 1.0e-12)
}

// ── 机制 4：错误哨兵（抽象类型没有 null 语义）─────────────────────────────

test "越界写入返回 Err 而不是崩溃" {
  let m = make(2, 2)
  match m.set(9, 9, 1.0) {
    Ok(_) => abort("应当失败：越界写入")
    Err(_) => ()
  }
}

test "负数尺寸返回 Err（不返回 nullptr 句柄）" {
  match Smoke::create(-1, 2) {
    Ok(_) => abort("应当失败：负数尺寸")
    Err(_) => ()
  }
}

// ── 机制 5：UTF-8 编码往返（moonbit_make_bytes → @utf8.decode_lossy）──────

test "中文错误信息逐字符往返正确" {
  // 这是**编码链路的端到端测试**：
  //   C++ 源文件里的 "下标越界"（靠 cc-flags 的 /utf-8 按 UTF-8 编入）
  //     → moonbit_make_bytes 原样搬运
  //     → @utf8.decode_lossy 解码
  //     → 与 MoonBit 源码里的同一字面量比较
  // 任何一环编码错（例如 MSVC 按 GBK 解释源文件）都会导致这里失败。
  let m = make(2, 2)
  match m.set(5, 5, 1.0) {
    Ok(_) => abort("应当失败")
    Err(msg) => {
      if msg != "下标越界" {
        abort("编码往返失败：期望「下标越界」，实际「\{msg}」")
      }
    }
  }
}
