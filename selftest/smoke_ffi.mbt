// selftest/smoke_ffi.mbt —— 自检包的私有 extern 声明层
//
// 每个函数的 C 侧实现在 selftest/smoke_stub.cpp。

///|
/// C++ 侧 Box 的 MoonBit 句柄（抽象类型 + finalizer）。
type SmokeMatrix

///|
/// 构建期自检：验证 C++17 与胶水层真的被编进来了。
extern "C" fn mb_smoke_probe() -> Int32 = "mb_smoke_probe"

///|
extern "C" fn mb_smoke_new(rows : Int32, cols : Int32) -> SmokeMatrix = "mb_smoke_new"

///|
/// 返回 -1 表示无效对象。
#borrow(handle)
extern "C" fn mb_smoke_rows(handle : SmokeMatrix) -> Int32 = "mb_smoke_rows"

///|
#borrow(handle)
extern "C" fn mb_smoke_set(
  handle : SmokeMatrix,
  i : Int32,
  j : Int32,
  v : Double,
) -> Int32 = "mb_smoke_set"

///|
#borrow(handle)
extern "C" fn mb_smoke_sum(handle : SmokeMatrix) -> Double = "mb_smoke_sum"

///|
/// 上一次操作的错误信息（UTF-8 字节）。
extern "C" fn mb_smoke_message() -> Bytes = "mb_smoke_message"
