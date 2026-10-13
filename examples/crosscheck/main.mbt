// examples/crosscheck/main.mbt —— 与纯 MoonBit 参考实现对拍
//
// 思路：同一个问题算两遍 —— 一遍走绑定（内部是 Eigen），
// 一遍走 reference 包里的纯 MoonBit 实现，然后逐元素比较。
//
// 为什么这个检查有意义：它同时验证了两件容易出错的事 ——
//   · 行主序契约（绑定的 to_array 与 from_array 必须首尾一致）
//   · 数值结果本身
// 如果两遍能对上，说明跨语言的数据搬运与算法调用都没有错位。
//
// 覆盖范围：矩阵乘法、2×2 与 3×3 解方程、2×2 与 3×3 行列式、
// 以及**奇异矩阵**（两边都必须判定为不可解）。
//
// 参考实现放在 reference 包里，不依赖任何第三方库，
// 因此即使 Eigen 没就绪也能跑，可以独立回答"是我搬错了，还是 Eigen 算错了"。

///|
/// 构造：失败直接终止（示例代码不做优雅恢复）。
fn mat(rows : Int, cols : Int, data : Array[Double]) -> @eigen.Matrix {
  match @eigen.Matrix::from_array(rows, cols, data) {
    Ok(m) => m
    Err(msg) => {
      println("构造矩阵失败: \{msg}")
      abort("构造矩阵失败")
    }
  }
}

///|
/// 把扁平数组格式化成 `[1, 2, 3]`。
/// 先按 1e6 取整再缩回，避免打印出 0.7999999999999999 这种浮点噪声。
fn show(a : Array[Double]) -> String {
  let mut s = "["
  for i = 0; i < a.length(); i = i + 1 {
    if i > 0 {
      s = s + ", "
    }
    s = s + "\{(a[i] * 1000000.0).round() / 1000000.0}"
  }
  s + "]"
}

///|
/// 导出绑定矩阵为扁平数组。
fn to_flat(m : @eigen.Matrix) -> Array[Double] {
  match m.to_array() {
    Ok(arr) => arr
    Err(msg) => {
      println("导出结果失败: \{msg}")
      abort("导出失败")
    }
  }
}

///|
/// 对拍一组：打印两边结果与最大绝对误差，返回是否一致。
fn compare(label : String, bound : Array[Double], reference : Array[Double]) -> Bool {
  let d = @ref.max_abs_diff(bound, reference)
  println("  绑定   \{label} = \{show(bound)}")
  println("  参考   \{label} = \{show(reference)}")
  println("  最大绝对误差 = \{d}")
  if @ref.approx_equal(bound, reference, 1.0e-12) {
    println("  ✓ 一致")
    true
  } else {
    println("  ✗ 不一致")
    false
  }
}

fn main {
  println("=== 对拍：绑定结果 vs 纯 MoonBit 参考实现 ===")
  println("")

  let mut failures = 0

  // ── [1] 矩阵乘法 3×4 · 4×2 ──────────────────────────────────────────────
  println("[1] 矩阵乘法  3×4 · 4×2")
  let m = 3
  let k = 4
  let n = 2
  let a_data : Array[Double] = [
    1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0,
  ]
  let b_data : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]

  let c_bound = match mat(m, k, a_data).mul(mat(k, n, b_data)) {
    Ok(x) => to_flat(x)
    Err(msg) => {
      println("  绑定乘法失败: \{msg}")
      abort("对拍失败")
    }
  }
  let c_ref = @ref.matmul(a_data, m, k, b_data, n)
  if !compare("A*B", c_bound, c_ref) {
    failures = failures + 1
  }
  println("")

  // ── [2] 解线性方程组 2×2 ───────────────────────────────────────────────
  // 手算：[[2,1],[1,3]] x = [3,5]  =>  x = [0.8, 1.4]
  println("[2] 解线性方程组  2×2")
  let a2 : Array[Double] = [2.0, 1.0, 1.0, 3.0]
  let b2 : Array[Double] = [3.0, 5.0]
  let x_bound2 = match mat(2, 2, a2).solve(mat(2, 1, b2)) {
    Ok(x) => to_flat(x)
    Err(msg) => {
      println("  绑定求解失败: \{msg}")
      abort("对拍失败")
    }
  }
  let x_ref2 = match @ref.solve(a2, 2, b2) {
    Some(x) => x
    None => {
      println("  参考实现判定为奇异 —— 与绑定不一致")
      abort("对拍失败")
    }
  }
  if !compare("x", x_bound2, x_ref2) {
    failures = failures + 1
  }
  println("")

  // ── [3] 解线性方程组 3×3 ───────────────────────────────────────────────
  // 取 A = [[1,2,3],[4,5,6],[7,8,10]]、已知解 [1,1,1]，
  // 则右端项 b = A·[1,1,1] = [6, 15, 25]。解回来必须正好是 [1,1,1]。
  println("[3] 解线性方程组  3×3（由已知解反推右端项）")
  let a3 : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 10.0]
  let b3 : Array[Double] = [6.0, 15.0, 25.0]
  let x_bound3 = match mat(3, 3, a3).solve(mat(3, 1, b3)) {
    Ok(x) => to_flat(x)
    Err(msg) => {
      println("  绑定求解失败: \{msg}")
      abort("对拍失败")
    }
  }
  let x_ref3 = match @ref.solve(a3, 3, b3) {
    Some(x) => x
    None => {
      println("  参考实现判定为奇异 —— 与绑定不一致")
      abort("对拍失败")
    }
  }
  if !compare("x", x_bound3, x_ref3) {
    failures = failures + 1
  }
  println("")

  // ── [4] 行列式 ─────────────────────────────────────────────────────────
  // 手算：det([[2,1],[1,3]]) = 5；det([[1,2,3],[4,5,6],[7,8,10]]) = -3
  println("[4] 行列式")
  let det_bound2 = match mat(2, 2, a2).det() {
    Ok(d) => d
    Err(msg) => {
      println("  绑定求行列式失败: \{msg}")
      abort("对拍失败")
    }
  }
  if !compare("det(2×2)", [det_bound2], [@ref.det(a2, 2)]) {
    failures = failures + 1
  }
  let det_bound3 = match mat(3, 3, a3).det() {
    Ok(d) => d
    Err(msg) => {
      println("  绑定求行列式失败: \{msg}")
      abort("对拍失败")
    }
  }
  if !compare("det(3×3)", [det_bound3], [@ref.det(a3, 3)]) {
    failures = failures + 1
  }
  println("")

  // ── [5] 奇异矩阵：两边都必须判定为不可解 ────────────────────────────────
  // 第二行是第一行的 2 倍，行列式为 0。
  // 这一组验证的不是"数值相等"，而是**错误判定的一致性**。
  println("[5] 奇异矩阵：两边都必须判定为不可解")
  let sing : Array[Double] = [1.0, 2.0, 2.0, 4.0]
  let sing_b : Array[Double] = [1.0, 2.0]
  let bound_rejected = match mat(2, 2, sing).solve(mat(2, 1, sing_b)) {
    Ok(_) => {
      println("  绑定：竟然给出了解（应当拒绝）")
      false
    }
    Err(msg) => {
      println("  绑定：拒绝求解 → \{msg}")
      true
    }
  }
  let ref_rejected = match @ref.solve(sing, 2, sing_b) {
    Some(_) => {
      println("  参考：竟然给出了解（应当拒绝）")
      false
    }
    None => {
      println("  参考：拒绝求解 → None")
      true
    }
  }
  if bound_rejected && ref_rejected {
    println("  ✓ 两边一致（都判定为不可解）")
  } else {
    println("  ✗ 两边不一致")
    failures = failures + 1
  }
  println("")

  // ── 结论 ───────────────────────────────────────────────────────────────
  if failures == 0 {
    println("对拍通过：5 组检查全部一致（含奇异矩阵的错误判定）。")
  } else {
    println("对拍失败：\{failures} 组不一致。")
    abort("对拍失败")
  }
}
