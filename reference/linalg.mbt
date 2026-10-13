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

// ── 解线性方程组与行列式 ─────────────────────────────────────────────────────
//
// solve 与 det 共用同一份消元逻辑（gauss_eliminate），刻意不写两套 ——
// 参考实现的价值在于"显然正确"，两份各写一遍只会让它们有机会各自跑偏。

///|
/// 高斯消元（部分主元法），**就地修改** `m`（n×n 行主序）与 `rhs`（长度 n）。
///
/// 返回 `(是否非奇异, 行交换带来的符号)`；符号供 det 使用。
///
/// 选主元不是可选项：不选主元时主元为 0 会直接除零，
/// 主元很小则误差被放大 —— 这是高斯消元最常见的实现缺陷。
fn gauss_eliminate(
  m : Array[Double],
  rhs : Array[Double],
  n : Int,
) -> (Bool, Double) {
  let mut sign = 1.0
  for col = 0; col < n; col = col + 1 {
    // 在 col 列、从 col 行往下找绝对值最大的元素
    let mut pivot = col
    let mut best = m[col * n + col].abs()
    for r = col + 1; r < n; r = r + 1 {
      let v = m[r * n + col].abs()
      if v > best {
        best = v
        pivot = r
      }
    }
    // 整列都是 0 → 奇异
    if best == 0.0 {
      return (false, sign)
    }
    // 换行（连带 rhs，并翻转符号）
    if pivot != col {
      for c = 0; c < n; c = c + 1 {
        let tmp = m[col * n + c]
        m[col * n + c] = m[pivot * n + c]
        m[pivot * n + c] = tmp
      }
      let tb = rhs[col]
      rhs[col] = rhs[pivot]
      rhs[pivot] = tb
      sign = 0.0 - sign
    }
    // 消去 col 列下方
    let p = m[col * n + col]
    for r = col + 1; r < n; r = r + 1 {
      let f = m[r * n + col] / p
      if f != 0.0 {
        for c = col; c < n; c = c + 1 {
          m[r * n + c] = m[r * n + c] - f * m[col * n + c]
        }
        rhs[r] = rhs[r] - f * rhs[col]
      }
    }
  }
  (true, sign)
}

///|
/// 复制前 len 个元素（对拍对象不该有副作用，所以先复制再改）。
fn copy_of(src : Array[Double], len : Int) -> Array[Double] {
  let out : Array[Double] = []
  for i = 0; i < len; i = i + 1 {
    out.push(src[i])
  }
  out
}

///|
/// 解 n 元线性方程组 `A x = b`（A 为 n×n 行主序）。
///
/// 奇异时返回 `None` —— 与绑定的 `Result::Err` 对应，
/// 因此对拍时可以同时覆盖"正常解"和"奇异判定"两条路径。
pub fn solve(a : Array[Double], n : Int, b : Array[Double]) -> Array[Double]? {
  let m = copy_of(a, n * n)
  let rhs = copy_of(b, n)
  let (ok, _) = gauss_eliminate(m, rhs, n)
  if !ok {
    return None
  }
  // 回代
  let x : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    x.push(0.0)
  }
  for i = n - 1; i >= 0; i = i - 1 {
    let mut s = rhs[i]
    for j = i + 1; j < n; j = j + 1 {
      s = s - m[i * n + j] * x[j]
    }
    x[i] = s / m[i * n + i]
  }
  Some(x)
}

///|
/// 行列式（消元后对角线之积 × 行交换符号）。奇异矩阵返回 `0.0`。
pub fn det(a : Array[Double], n : Int) -> Double {
  let m = copy_of(a, n * n)
  // det 不需要右端项，但共用消元函数要一个同样长度的数组
  let dummy : Array[Double] = []
  for i = 0; i < n; i = i + 1 {
    dummy.push(0.0)
  }
  let (ok, sign) = gauss_eliminate(m, dummy, n)
  if !ok {
    return 0.0
  }
  let mut d = sign
  for i = 0; i < n; i = i + 1 {
    d = d * m[i * n + i]
  }
  d
}
