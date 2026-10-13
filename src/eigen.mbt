// src/eigen.mbt —— MoonBit 公开 API 层（本项目的主要实现语言所在）
//
// 上层用户只与这一层打交道：没有句柄、没有 FixedArray、没有错误码。
//
// 设计取向：
//   · 错误用 Result[T, String] 表达，不抛异常 —— 语法稳定、强制处理。
//   · 维度检查、错误信息取用、格式化输出都在 MoonBit 里做，
//     C++ 侧只保留"把模板实例化掉"这一件无法在 MoonBit 完成的事。
//
// ⚠️ 未编译验证：MoonBit 工具链安装中，本文件尚未通过 moon check。
//    需要用本机编译器校对的 API（详见 docs/PITFALLS.md 第 8 节）：
//    FixedArray::from_array、Array::from_fixed_array、Double::round /
//    to_int / to_double、StringBuilder 的方法名、字符串插值语法。

/// 动态尺寸的双精度矩阵。
pub struct Matrix {
  handle : EigenMatrix
}

// ---------------------------------------------------------------------------
// 内部工具
// ---------------------------------------------------------------------------

/// 取出 C 侧记录的上一次错误信息。
fn last_error() -> String {
  @utf8.decode_lossy(mb_eigen_last_error())
}

/// 统一的有效性检查：rows() < 0 表示 C 侧返回了错误哨兵。
fn ensure_valid(handle : EigenMatrix) -> Result[Unit, String] {
  if mb_eigen_matrix_rows(handle) < 0 {
    Err(last_error())
  } else {
    Ok(())
  }
}

/// 把 C 侧返回的句柄包成 Matrix，失败则转成 Err。
fn wrap(handle : EigenMatrix) -> Result[Matrix, String] {
  match ensure_valid(handle) {
    Ok(_) => Ok({ handle })
    Err(msg) => Err(msg)
  }
}

/// 调用二元运算的公共路径：op 0=加 1=减 2=乘。
fn binary(self : Matrix, other : Matrix, op : Int) -> Result[Matrix, String] {
  wrap(mb_eigen_matrix_binary(self.handle, other.handle, op))
}

// ---------------------------------------------------------------------------
// 构造
// ---------------------------------------------------------------------------

/// 全零矩阵。
pub fn Matrix::zeros(rows : Int, cols : Int) -> Result[Matrix, String] {
  wrap(mb_eigen_matrix_new(rows, cols))
}

/// 从行主序的一维数组构造矩阵，要求 data.length() == rows * cols。
pub fn Matrix::from_array(
  rows : Int,
  cols : Int,
  data : Array[Double],
) -> Result[Matrix, String] {
  if rows < 0 || cols < 0 {
    return Err("矩阵尺寸不能为负")
  }
  if data.length() != rows * cols {
    return Err(
      "数据长度 \{data.length()} 与 rows*cols = \{rows * cols} 不匹配",
    )
  }
  let fixed = FixedArray::from_array(data)
  wrap(mb_eigen_matrix_from_array(rows, cols, fixed, fixed.length()))
}

// ---------------------------------------------------------------------------
// 元信息与元素访问
// ---------------------------------------------------------------------------

pub fn Matrix::rows(self : Matrix) -> Int {
  mb_eigen_matrix_rows(self.handle)
}

pub fn Matrix::cols(self : Matrix) -> Int {
  mb_eigen_matrix_cols(self.handle)
}

pub fn Matrix::get(self : Matrix, i : Int, j : Int) -> Result[Double, String] {
  if i < 0 || j < 0 || i >= self.rows() || j >= self.cols() {
    return Err("下标 (\{i}, \{j}) 越界：矩阵尺寸为 \{self.rows()}x\{self.cols()}")
  }
  Ok(mb_eigen_matrix_get(self.handle, i, j))
}

pub fn Matrix::set(
  self : Matrix,
  i : Int,
  j : Int,
  value : Double,
) -> Result[Unit, String] {
  if i < 0 || j < 0 || i >= self.rows() || j >= self.cols() {
    return Err("下标 (\{i}, \{j}) 越界：矩阵尺寸为 \{self.rows()}x\{self.cols()}")
  }
  if mb_eigen_matrix_set(self.handle, i, j, value) != 0 {
    return Err(last_error())
  }
  Ok(())
}

/// 导出为行主序的一维数组。
pub fn Matrix::to_array(self : Matrix) -> Result[Array[Double], String] {
  let n = self.rows() * self.cols()
  let out = FixedArray::make(n, 0.0)
  if mb_eigen_matrix_copy_to(self.handle, out, n) != 0 {
    return Err(last_error())
  }
  Ok(Array::from_fixed_array(out))
}

// ---------------------------------------------------------------------------
// 运算
// ---------------------------------------------------------------------------

pub fn Matrix::add(self : Matrix, other : Matrix) -> Result[Matrix, String] {
  binary(self, other, 0)
}

pub fn Matrix::sub(self : Matrix, other : Matrix) -> Result[Matrix, String] {
  binary(self, other, 1)
}

pub fn Matrix::mul(self : Matrix, other : Matrix) -> Result[Matrix, String] {
  binary(self, other, 2)
}

pub fn Matrix::scale(self : Matrix, k : Double) -> Result[Matrix, String] {
  wrap(mb_eigen_matrix_scale(self.handle, k))
}

pub fn Matrix::transpose(self : Matrix) -> Result[Matrix, String] {
  wrap(mb_eigen_matrix_transpose(self.handle))
}

/// 解线性方程组 Ax = b。
pub fn Matrix::solve(self : Matrix, b : Matrix) -> Result[Matrix, String] {
  wrap(mb_eigen_matrix_solve(self.handle, b.handle))
}

/// 内积：同尺寸时为其逐元素乘积之和（向量即点积）。
pub fn Matrix::dot(self : Matrix, other : Matrix) -> Result[Double, String] {
  if self.rows() * self.cols() != other.rows() * other.cols() {
    return Err("内积要求两个矩阵元素个数相同")
  }
  Ok(mb_eigen_matrix_dot(self.handle, other.handle))
}

/// Frobenius 范数。
pub fn Matrix::norm(self : Matrix) -> Double {
  mb_eigen_matrix_norm(self.handle)
}

/// 行列式，要求方阵。
pub fn Matrix::det(self : Matrix) -> Result[Double, String] {
  if self.rows() != self.cols() {
    return Err("行列式要求方阵，当前为 \{self.rows()}x\{self.cols()}")
  }
  Ok(mb_eigen_matrix_det(self.handle))
}

// ---------------------------------------------------------------------------
// 纯 MoonBit 的价值点：格式化输出
//
// 这一部分完全不碰 FFI —— 它说明本项目不只是"把 C++ 抄一遍"，
// MoonBit 侧确实在提供自己的东西。
// ---------------------------------------------------------------------------

/// 把矩阵渲染成可读的多行字符串（列对齐）。
pub fn Matrix::to_string(self : Matrix) -> String {
  if self.rows() < 0 {
    return "<无效矩阵: \{last_error()}>"
  }
  let mut sb = StringBuilder::new()
  sb.write_string("Matrix(\{self.rows()}x\{self.cols()})")
  for i = 0; i < self.rows(); i = i + 1 {
    sb.write_char('\n')
    sb.write_string("  [")
    for j = 0; j < self.cols(); j = j + 1 {
      if j > 0 {
        sb.write_string(", ")
      }
      let v = mb_eigen_matrix_get(self.handle, i, j)
      sb.write_string(format_double(v))
    }
    sb.write_string("]")
  }
  sb.to_string()
}

/// 把 double 格式化成定长小数，便于列对齐。
fn format_double(v : Double) -> String {
  let scaled = (v * 1000.0).round()
  let negative = scaled < 0.0
  let abs_scaled = if negative { -scaled } else { scaled }
  let whole = (abs_scaled / 1000.0).to_int()
  let frac = (abs_scaled - whole.to_double() * 1000.0).to_int()
  let sign = if negative { "-" } else { "" }
  if frac < 10 {
    "\{sign}\{whole}.00\{frac}"
  } else if frac < 100 {
    "\{sign}\{whole}.0\{frac}"
  } else {
    "\{sign}\{whole}.\{frac}"
  }
}
