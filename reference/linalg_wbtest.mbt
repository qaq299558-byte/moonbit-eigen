// reference/linalg_wbtest.mbt —— 参考实现自己的测试
//
// 对拍对象本身也必须被测：如果参考实现是错的，
// 那它和绑定"对上了"说明不了任何事（两边可能错得一样）。
// 这里用**手算得出的期望值**，而不是"跑一遍记下来"的结果。

///|
test "matmul：3×4 乘 4×2（手算核对）" {
  // A = [[1,2,3,4],[5,6,7,8],[9,10,11,12]]，B = [[1,2],[3,4],[5,6],[7,8]]
  // 手算：A*B = [[50,60],[114,140],[178,220]]
  let a : Array[Double] = [
    1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0,
  ]
  let b : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
  let c = matmul(a, 3, 4, b, 2)
  let expected : Array[Double] = [50.0, 60.0, 114.0, 140.0, 178.0, 220.0]
  if !(approx_equal(c, expected, 1.0e-12)) {
    abort("matmul 结果与手算不符，最大误差 = \{max_abs_diff(c, expected)}")
  }
}

///|
test "matmul：单位矩阵是乘法单位元" {
  let a : Array[Double] = [1.0, 2.0, 3.0, 4.0]
  let id : Array[Double] = [1.0, 0.0, 0.0, 1.0]
  let c = matmul(a, 2, 2, id, 2)
  if !(approx_equal(c, a, 1.0e-12)) {
    abort("A*I 应当等于 A，最大误差 = \{max_abs_diff(c, a)}")
  }
}

///|
test "transpose：两次转置回到原样" {
  let a : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
  let t = transpose(transpose(a, 2, 3), 3, 2)
  if !(approx_equal(t, a, 1.0e-12)) {
    abort("两次转置应当回到原样")
  }
}

///|
test "transpose：确实按行主序重排" {
  // [[1,2,3],[4,5,6]] 转置后是 [[1,4],[2,5],[3,6]]
  let a : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
  let expected : Array[Double] = [1.0, 4.0, 2.0, 5.0, 3.0, 6.0]
  let t = transpose(a, 2, 3)
  if !(approx_equal(t, expected, 1.0e-12)) {
    abort("转置结果错误，最大误差 = \{max_abs_diff(t, expected)}")
  }
}

///|
test "dot 与 norm" {
  let a : Array[Double] = [1.0, 2.0, 3.0]
  let b : Array[Double] = [4.0, 5.0, 6.0]
  if !(approx_equal([dot(a, b)], [32.0], 1.0e-12)) {
    abort("点积应为 32")
  }
  // 3-4-5 直角三角形
  let tri : Array[Double] = [3.0, 4.0]
  if !(approx_equal([norm(tri)], [5.0], 1.0e-12)) {
    abort("3-4-5 的范数应为 5")
  }
}

///|
test "max_abs_diff：长度不同返回 Infinity" {
  let a : Array[Double] = [1.0]
  let b : Array[Double] = [1.0, 2.0]
  let d = max_abs_diff(a, b)
  if d < 1.0e300 {
    abort("长度不一致时应当返回 Infinity")
  }
}

// ── solve / det ──────────────────────────────────────────────────────────────
//
// 下面这些期望值全部是手算的（不是跑一遍记下来的）。
// 参考实现若是错的，"和它对上"说明不了任何事。

///|
test "solve：2×2（手算 0.8 / 1.4）" {
  // [[2,1],[1,3]] x = [3,5]  =>  x = [0.8, 1.4]
  let a : Array[Double] = [2.0, 1.0, 1.0, 3.0]
  let b : Array[Double] = [3.0, 5.0]
  match solve(a, 2, b) {
    Some(x) =>
      if !approx_equal(x, [0.8, 1.4], 1.0e-12) {
        abort("解应为 [0.8, 1.4]，最大误差 = \{max_abs_diff(x, [0.8, 1.4])}")
      }
    None => abort("不应判定为奇异")
  }
}

///|
test "solve：必须换行才能解（这条专门盯部分主元法）" {
  // [[0,1],[1,0]] x = [2,3]  =>  x = [3,2]
  // 首元素为 0：不选主元的实现会在这里直接除零。
  let a : Array[Double] = [0.0, 1.0, 1.0, 0.0]
  let b : Array[Double] = [2.0, 3.0]
  match solve(a, 2, b) {
    Some(x) =>
      if !approx_equal(x, [3.0, 2.0], 1.0e-12) {
        abort("应解出 [3, 2]，最大误差 = \{max_abs_diff(x, [3.0, 2.0])}")
      }
    None => abort("不应判定为奇异")
  }
}

///|
test "solve：奇异矩阵返回 None" {
  // 第二行是第一行的 2 倍
  let a : Array[Double] = [1.0, 2.0, 2.0, 4.0]
  let b : Array[Double] = [1.0, 2.0]
  match solve(a, 2, b) {
    Some(_) => abort("奇异矩阵不应给出解")
    None => ()
  }
}

///|
test "solve：3×3（由已知解反推右端项）" {
  // 取 A = [[1,2,3],[4,5,6],[7,8,10]]，令 x = [1,1,1]，
  // 则 b = A x = [6, 15, 25]；解回来应当正好是 [1,1,1]。
  let a : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 10.0]
  let b : Array[Double] = [6.0, 15.0, 25.0]
  match solve(a, 3, b) {
    Some(x) =>
      if !approx_equal(x, [1.0, 1.0, 1.0], 1.0e-12) {
        abort("应解出 [1,1,1]，最大误差 = \{max_abs_diff(x, [1.0, 1.0, 1.0])}")
      }
    None => abort("不应判定为奇异")
  }
}

///|
test "det：2×2 与 3×3（手算）" {
  if !approx_equal([det([2.0, 1.0, 1.0, 3.0], 2)], [5.0], 1.0e-12) {
    abort("det([[2,1],[1,3]]) 应为 5")
  }
  // 3×3 按第一行展开：1*(50-48) - 2*(40-42) + 3*(32-35) = 2 + 4 - 9 = -3
  let a3 : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 10.0]
  if !approx_equal([det(a3, 3)], [-3.0], 1.0e-12) {
    abort("3×3 行列式应为 -3，实际 = \{det(a3, 3)}")
  }
}

///|
test "det：奇异矩阵为 0；换行必须翻转符号" {
  if !approx_equal([det([1.0, 2.0, 2.0, 4.0], 2)], [0.0], 1.0e-12) {
    abort("奇异矩阵的行列式应为 0")
  }
  // [[0,1],[1,0]] 的 det = -1，必须换行才能算出来；
  // 符号处理写错会得到 +1 —— 这条测试专门盯这一点。
  if !approx_equal([det([0.0, 1.0, 1.0, 0.0], 2)], [-1.0], 1.0e-12) {
    abort("det([[0,1],[1,0]]) 应为 -1（换行要翻符号）")
  }
}

///|
test "solve / det 不修改调用方的数组" {
  let a : Array[Double] = [2.0, 1.0, 1.0, 3.0]
  let b : Array[Double] = [3.0, 5.0]
  let _ = solve(a, 2, b)
  let _ = det(a, 2)
  if !approx_equal(a, [2.0, 1.0, 1.0, 3.0], 1.0e-12) {
    abort("solve / det 不应修改传入的矩阵")
  }
  if !approx_equal(b, [3.0, 5.0], 1.0e-12) {
    abort("solve 不应修改传入的右端项")
  }
}
