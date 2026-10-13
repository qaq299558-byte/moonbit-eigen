// reference/linalg.mbt —— 纯 MoonBit 的线性代数参考实现（行主序）
//
// ── 这个包是干什么的 ─────────────────────────────────────────────────────────
//
// 它是绑定的**独立对拍对象**，不是给用户用的功能库。
//
// 为什么值得单独存在：
//   · 跨语言项目最容易错的两件事是**存储布局**和**数据搬运**，
//     而它们都不会报错、只会算错 —— 必须靠"两份独立实现互相印证"来抓。
//   · 参考实现完全在 MoonBit 侧、不依赖任何第三方库，
//     因此**即使 Eigen 没就绪（甚至没安装）也能跑**，
//     可以独立回答"是我搬错了，还是 Eigen 算错了"。
//   · 它同时是"MoonBit 足以表达数值算法"的一个具体证据。
//
// 实测结果：与绑定的矩阵乘法对拍，最大绝对误差为 0（见 examples/crosscheck）。

///|
/// 行主序矩阵乘法：`a` 是 m×k，`b` 是 k×n，返回 m×n。
///
/// 前置条件（不检查，调用方保证）：
///   · `a.length() == m * k`
///   · `b.length() == k * n`
pub fn matmul(
  a : Array[Double],
  m : Int,
  k : Int,
  b : Array[Double],
  n : Int,
) -> Array[Double] {
  // ⚠️ 不要写 `let mut out`：Array::push 接收 self，通过方法修改内容
  //    不需要绑定可变，否则 moonc 报 error 15 unused_mut。
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

///|
/// 行主序转置：m×n → n×m。
pub fn transpose(a : Array[Double], m : Int, n : Int) -> Array[Double] {
  let out : Array[Double] = []
  for j = 0; j < n; j = j + 1 {
    for i = 0; i < m; i = i + 1 {
      out.push(a[i * n + j])
    }
  }
  out
}

///|
/// 逐元素乘积之和（对向量即点积）。
pub fn dot(a : Array[Double], b : Array[Double]) -> Double {
  let mut acc = 0.0
  let len = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < len; i = i + 1 {
    acc = acc + a[i] * b[i]
  }
  acc
}

///|
/// Frobenius 范数。
pub fn norm(a : Array[Double]) -> Double {
  dot(a, a).sqrt()
}

///|
/// 两个等长数组的最大绝对误差。
///
/// 长度不一致时返回 `Infinity` —— 对拍场景下"长度不同"就是一种失败，
/// 用无穷大可以直接触发容差判断，不必让调用方额外分支。
pub fn max_abs_diff(a : Array[Double], b : Array[Double]) -> Double {
  if a.length() != b.length() {
    return 1.0 / 0.0
  }
  let mut worst = 0.0
  for i = 0; i < a.length(); i = i + 1 {
    let d = a[i] - b[i]
    let ad = if d < 0.0 { -d } else { d }
    if ad > worst {
      worst = ad
    }
  }
  worst
}

///|
/// 逐元素近似相等（对拍判定用）。
pub fn approx_equal(a : Array[Double], b : Array[Double], tol : Double) -> Bool {
  max_abs_diff(a, b) <= tol
}
