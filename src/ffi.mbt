// src/ffi.mbt —— 私有 FFI 声明层
//
// 官方 agent skill 的建议：extern 声明保持私有，只通过下一层的
// 安全公开 API 暴露给用户（见 src/eigen.mbt）。
//
// 每个函数的 C 侧实现见 src/eigen_shim.cpp，命名一一对应。

/// C++ 侧 MatrixBox 的 MoonBit 句柄。
///
/// 抽象类型（type T）：官方 ABI 表规定它对应一个指针，且必须是
/// 合法的 MoonBit 对象 —— 这正是 moonbit_make_external_object 的返回值。
/// 注意：不能用 #external —— 那样内存管理系统会忽略它，finalizer 不会跑。
type EigenMatrix

/// 构建期自检：验证 C++17 与 Eigen 版本真的被编进来了。
extern "C" fn mb_eigen_shim_probe() -> Int = "mb_eigen_shim_probe"

extern "C" fn mb_eigen_matrix_new(rows : Int, cols : Int) -> EigenMatrix = "mb_eigen_matrix_new"

// data 是 FixedArray[Double]（C ABI: double*）。
// 用 #borrow：shim 只在调用期间读取它，不保存引用。
#borrow(data)
extern "C" fn mb_eigen_matrix_from_array(
  rows : Int,
  cols : Int,
  data : FixedArray[Double],
  len : Int,
) -> EigenMatrix = "mb_eigen_matrix_from_array"

/// 返回 -1 表示"无效矩阵 / 上一次操作失败"。
extern "C" fn mb_eigen_matrix_rows(handle : EigenMatrix) -> Int = "mb_eigen_matrix_rows"
extern "C" fn mb_eigen_matrix_cols(handle : EigenMatrix) -> Int = "mb_eigen_matrix_cols"

extern "C" fn mb_eigen_matrix_get(handle : EigenMatrix, i : Int, j : Int) -> Double = "mb_eigen_matrix_get"
extern "C" fn mb_eigen_matrix_set(handle : EigenMatrix, i : Int, j : Int, v : Double) -> Int = "mb_eigen_matrix_set"

/// out 由调用方分配，长度必须等于 rows*cols。
/// 用 #borrow：shim 只往里写，不保存引用。
#borrow(out)
extern "C" fn mb_eigen_matrix_copy_to(handle : EigenMatrix, out : FixedArray[Double], len : Int) -> Int = "mb_eigen_matrix_copy_to"

/// op: 0=加 1=减 2=乘
extern "C" fn mb_eigen_matrix_binary(a : EigenMatrix, b : EigenMatrix, op : Int) -> EigenMatrix = "mb_eigen_matrix_binary"

extern "C" fn mb_eigen_matrix_scale(a : EigenMatrix, k : Double) -> EigenMatrix = "mb_eigen_matrix_scale"
extern "C" fn mb_eigen_matrix_transpose(a : EigenMatrix) -> EigenMatrix = "mb_eigen_matrix_transpose"
extern "C" fn mb_eigen_matrix_solve(a : EigenMatrix, b : EigenMatrix) -> EigenMatrix = "mb_eigen_matrix_solve"

extern "C" fn mb_eigen_matrix_dot(a : EigenMatrix, b : EigenMatrix) -> Double = "mb_eigen_matrix_dot"
extern "C" fn mb_eigen_matrix_norm(a : EigenMatrix) -> Double = "mb_eigen_matrix_norm"
extern "C" fn mb_eigen_matrix_det(a : EigenMatrix) -> Double = "mb_eigen_matrix_det"

/// 上一次操作的错误信息（UTF-8 字节）。成功时为空。
/// 用 Bytes 而不是 String：C 侧用 moonbit_make_bytes 构造，
/// 在 MoonBit 侧再解码，这是官方 agent skill 推荐的做法。
extern "C" fn mb_eigen_last_error() -> Bytes = "mb_eigen_last_error"
