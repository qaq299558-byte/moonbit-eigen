// selftest/smoke.mbt —— 自检包的公开 API
//
// 刻意保持极薄：这个包的目的不是提供功能，而是**证明机制可用**。
// 结构与 src/eigen.mbt 一致（Result 错误处理 + 错误信息解码），
// 这样它对机制的验证才具有代表性。

///|
/// 一个极简的二维矩阵（仅用于自检，不做任何实际数值功能）。
pub struct Smoke {
  handle : SmokeMatrix
}

///|
/// 取出 C 侧记录的错误信息。
///
/// `[:]` 不能省：官方 encoding/utf8 的接口是
/// `pub fn decode_lossy(BytesView, ignore_bom? : Bool) -> String`，
/// 收的是 BytesView 而不是 Bytes。
fn smoke_error() -> String {
  @utf8.decode_lossy(mb_smoke_message()[:])
}

///|
/// 创建 rows×cols 的零矩阵。
pub fn Smoke::create(rows : Int32, cols : Int32) -> Result[Smoke, String] {
  let handle = mb_smoke_new(rows, cols)
  if mb_smoke_rows(handle) < 0 {
    Err(smoke_error())
  } else {
    // 显式写字段名：`{ handle }` 这种简写会触发 ambiguous_block 警告
    // （warning 22：编译器无法区分"结构体字面量"与"块表达式"）。
    Ok({ handle: handle })
  }
}

///|
pub fn Smoke::rows(self : Smoke) -> Int32 {
  mb_smoke_rows(self.handle)
}

///|
pub fn Smoke::set(
  self : Smoke,
  i : Int32,
  j : Int32,
  v : Double,
) -> Result[Unit, String] {
  if mb_smoke_set(self.handle, i, j, v) != 0 {
    Err(smoke_error())
  } else {
    Ok(())
  }
}

///|
pub fn Smoke::sum(self : Smoke) -> Double {
  mb_smoke_sum(self.handle)
}

///|
/// 构建期自检探针的公开封装（供示例 / 脚本调用）。
pub fn probe() -> Int32 {
  mb_smoke_probe()
}
