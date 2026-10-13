// examples/crosscheck/main.mbt —— 与纯 MoonBit 参考实现对拍
//
// 思路：
//   1. 用绑定的 Matrix 做一次矩阵乘法；
//   2. 用纯 MoonBit 的三重循环对同一批数据做一次乘法；
//   3. 逐元素比较，输出最大绝对误差。
//
// 为什么这个检查有意义：它同时验证了两件容易出错的事 ——
//   · 行主序契约（绑定的 to_array 与 from_array 必须首尾一致）
//   · 数值结果本身
// 如果 1 和 2 能对上，说明跨语言的数据搬运没有错位。
//
// ⚠️ 未编译验证：工具链就绪后需校对。

/// 纯 MoonBit 参考实现：行主序的 m×k 乘 k×n。
fn matmul_ref(
  a : Array[Double],
  b : Array[Double],
  m : Int,
  k : Int,
  n : Int,
) -> Array[Double] {
  // 不加 mut：Array::push 接收 self，通过方法改内容不需要绑定可变
  // （moonc 会报 error 15 unused_mut）。
  let out : Array[Double] = []
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let mut acc = 0.0
      for p = 0; p < k; p = p + 1 {
        acc = acc + a[i * k + p] * b[p * n + j]
      }
      out.push(acc)
    }
  }
  out
}

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

fn main {
  println("=== 对拍：绑定结果 vs 纯 MoonBit 三重循环 ===")
  println("")

  let m = 3
  let k = 4
  let n = 2

  // A: 3x4，取值 1..12（行主序）
  let a_data : Array[Double] = [
    1.0, 2.0, 3.0, 4.0,
    5.0, 6.0, 7.0, 8.0,
    9.0, 10.0, 11.0, 12.0,
  ]
  // B: 4x2，取值 1..8（行主序）
  let b_data : Array[Double] = [
    1.0, 2.0,
    3.0, 4.0,
    5.0, 6.0,
    7.0, 8.0,
  ]

  let a = mat(m, k, a_data)
  let b = mat(k, n, b_data)

  println("A = \{a.to_string()}")
  println("B = \{b.to_string()}")
  println("")

  // ── 路径 1：绑定 ─────────────────────────────────────────────────────────
  let c_bound_m = match a.mul(b) {
    Ok(x) => x
    Err(msg) => {
      println("绑定乘法失败: \{msg}")
      return
    }
  }
  let c_bound = match c_bound_m.to_array() {
    Ok(arr) => arr
    Err(msg) => {
      println("导出结果失败: \{msg}")
      return
    }
  }

  // ── 路径 2：纯 MoonBit 参考实现 ─────────────────────────────────────────
  let c_ref = matmul_ref(a_data, b_data, m, k, n)

  println("绑定结果 A*B = \{c_bound_m.to_string()}")
  println("")

  // ── 比较 ────────────────────────────────────────────────────────────────
  if c_bound.length() != c_ref.length() {
    println("长度不一致：绑定 \{c_bound.length()} vs 参考 \{c_ref.length()}")
    abort("对拍失败")
  }

  let mut max_diff = 0.0
  for i = 0; i < c_bound.length(); i = i + 1 {
    let d = c_bound[i] - c_ref[i]
    let ad = if d < 0.0 { -d } else { d }
    if ad > max_diff {
      max_diff = ad
    }
    println("  [{i}] 绑定=\{c_bound[i]}  参考=\{c_ref[i]}")
  }

  println("")
  println("最大绝对误差 = \{max_diff}")

  // 全是整数运算，应当完全一致；留一点浮点容差。
  if max_diff > 1.0e-12 {
    println("对拍失败：误差超出容差")
    abort("对拍失败")
  }
  println("对拍通过：绑定的数据搬运与乘法结果与纯 MoonBit 实现一致。")
}
