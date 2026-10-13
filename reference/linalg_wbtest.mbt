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
