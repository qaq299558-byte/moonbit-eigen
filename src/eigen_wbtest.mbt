// src/eigen_wbtest.mbt —— 单元测试（**WhiteBox** 测试）
//
// 为什么是 _wbtest.mbt 而不是 _test.mbt？
//   MoonBit 的两种测试文件语义不同：
//     · foo_test.mbt   → BlackBox：只能访问包的 **public** 成员，
//                        需要用包别名限定（模拟真实用户的视角）
//     · foo_wbtest.mbt → WhiteBox：可以访问包的**全部**成员
//   本文件里有测试要调用 ffi.mbt 中的私有 extern 声明
//   （mb_eigen_shim_probe、mb_eigen_matrix_*），BlackBox 测试看不到它们，
//   放在 _test.mbt 里会直接编译失败。
//
// 出处：官方 "Writing Tests" 文档的 BlackBox / WhiteBox 一节
//       https://docs.moonbitlang.com/en/latest/language/tests.html
//
// 测试覆盖两类东西：
//   · 正确性：与手算结果对比（小尺寸，可核对）
//   · 错误路径：维度不匹配、越界、奇异矩阵 —— 跨语言边界最容易出事的地方

/// 断言两个 double 在容差内相等。
fn assert_close(actual : Double, expected : Double, tol : Double) -> Unit {
  let diff = if actual > expected { actual - expected } else { expected - actual }
  if diff > tol {
    abort("期望 \{expected}，实际 \{actual}（差值 \{diff} 超过容差 \{tol}）")
  }
}

/// 构造一个已知矩阵：[[1,2],[3,4]]
fn m2x2() -> Matrix {
  match Matrix::from_array(2, 2, [1.0, 2.0, 3.0, 4.0]) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
}

/// 取值的简写，测试里到处要用。
fn val(m : Matrix, i : Int, j : Int) -> Double {
  match m.get(i, j) {
    Ok(v) => v
    Err(msg) => abort("读取 (\{i},\{j}) 失败: \{msg}")
  }
}

test "shim probe 报告 C++17 与 Eigen 3.x" {
  // 最小可信度证据：能返回非零就说明 C++ 胶水真的被编译进构建了。
  // 这个测试同时是技术穿刺的判定依据（见 scripts/spike.ps1 与 docs/ROADMAP.md）。
  let probe = mb_eigen_shim_probe()
  if probe < 17000 {
    abort("probe 返回值异常: \{probe}")
  }
}

test "zeros 创建正确的尺寸" {
  let m = match Matrix::zeros(3, 4) {
    Ok(m) => m
    Err(msg) => abort("创建失败: \{msg}")
  }
  if m.rows() != 3 || m.cols() != 4 {
    abort("尺寸错误: \{m.rows()}x\{m.cols()}")
  }
}

test "from_array 与 to_array 往返一致" {
  let data : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
  let m = match Matrix::from_array(2, 3, data) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
  let back = match m.to_array() {
    Ok(a) => a
    Err(msg) => abort("导出失败: \{msg}")
  }
  if back.length() != data.length() {
    abort("长度不一致")
  }
  for i = 0; i < data.length(); i = i + 1 {
    assert_close(back[i], data[i], 1.0e-12)
  }
}

test "元素读写" {
  let m = match Matrix::zeros(2, 2) {
    Ok(m) => m
    Err(msg) => abort("创建失败: \{msg}")
  }
  match m.set(1, 0, 7.5) {
    Ok(_) => ()
    Err(msg) => abort("写入失败: \{msg}")
  }
  assert_close(val(m, 1, 0), 7.5, 1.0e-12)
}

test "矩阵乘法与手算结果一致" {
  // [[1,2],[3,4]] * [[5,6],[7,8]] = [[19,22],[43,50]]
  let a = m2x2()
  let b = match Matrix::from_array(2, 2, [5.0, 6.0, 7.0, 8.0]) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
  let c = match a.mul(b) {
    Ok(m) => m
    Err(msg) => abort("乘法失败: \{msg}")
  }
  assert_close(val(c, 0, 0), 19.0, 1.0e-9)
  assert_close(val(c, 0, 1), 22.0, 1.0e-9)
  assert_close(val(c, 1, 0), 43.0, 1.0e-9)
  assert_close(val(c, 1, 1), 50.0, 1.0e-9)
}

test "加減法" {
  let a = m2x2()
  let b = match Matrix::from_array(2, 2, [5.0, 6.0, 7.0, 8.0]) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
  let sum = match a.add(b) {
    Ok(m) => m
    Err(msg) => abort("加法失败: \{msg}")
  }
  assert_close(val(sum, 0, 0), 6.0, 1.0e-12)
  assert_close(val(sum, 1, 1), 12.0, 1.0e-12)

  let diff = match b.sub(a) {
    Ok(m) => m
    Err(msg) => abort("减法失败: \{msg}")
  }
  assert_close(val(diff, 0, 0), 4.0, 1.0e-12)
  assert_close(val(diff, 1, 1), 4.0, 1.0e-12)
}

test "行列式与手算一致" {
  // det([[1,2],[3,4]]) = -2
  match m2x2().det() {
    Ok(d) => assert_close(d, -2.0, 1.0e-9)
    Err(msg) => abort("行列式失败: \{msg}")
  }
}

test "转置" {
  let m = match Matrix::from_array(2, 3, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
  let t = match m.transpose() {
    Ok(m) => m
    Err(msg) => abort("转置失败: \{msg}")
  }
  if t.rows() != 3 || t.cols() != 2 {
    abort("转置后尺寸错误: \{t.rows()}x\{t.cols()}")
  }
  // 行主序：原矩阵 (1,2) = 6，转置后应在 (2,1)
  assert_close(val(t, 2, 1), 6.0, 1.0e-12)
}

test "数乘与范数" {
  let m = m2x2()
  let scaled = match m.scale(2.0) {
    Ok(m) => m
    Err(msg) => abort("数乘失败: \{msg}")
  }
  assert_close(val(scaled, 1, 1), 8.0, 1.0e-12)
  // Frobenius 范数 = sqrt(1+4+9+16) = sqrt(30)
  assert_close(m.norm(), 5.477225575051661, 1.0e-9)
}

test "内积" {
  // [1,2,3] · [4,5,6] = 32
  let a = match Matrix::from_array(1, 3, [1.0, 2.0, 3.0]) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
  let b = match Matrix::from_array(3, 1, [4.0, 5.0, 6.0]) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
  match a.dot(b) {
    Ok(v) => assert_close(v, 32.0, 1.0e-12)
    Err(msg) => abort("内积失败: \{msg}")
  }
}

test "解线性方程组 Ax=b" {
  // [[2,1],[1,3]] x = [3,5]  =>  x = [0.8, 1.4]
  let a = match Matrix::from_array(2, 2, [2.0, 1.0, 1.0, 3.0]) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
  let b = match Matrix::from_array(2, 1, [3.0, 5.0]) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
  let x = match a.solve(b) {
    Ok(m) => m
    Err(msg) => abort("求解失败: \{msg}")
  }
  assert_close(val(x, 0, 0), 0.8, 1.0e-9)
  assert_close(val(x, 1, 0), 1.4, 1.0e-9)
}

test "to_string 渲染出可读文本" {
  let s = m2x2().to_string()
  // 只断言结构性内容，不锁死浮点格式（v2 会改成对齐输出）
  if !s.contains("2x2") {
    abort("to_string 应包含尺寸信息，实际为: \{s}")
  }
}

// ── 错误路径：跨语言边界最容易出事的地方 ──────────────────────────────────

test "尺寸不匹配的加法返回 Err 而不是崩溃" {
  let a = m2x2()
  let b = match Matrix::zeros(3, 3) {
    Ok(m) => m
    Err(msg) => abort("创建失败: \{msg}")
  }
  match a.add(b) {
    Ok(_) => abort("应当失败：尺寸不匹配的加法不该成功")
    Err(msg) => if msg.length() == 0 { abort("错误信息不应为空") }
  }
}

test "非方阵求行列式返回 Err" {
  let m = match Matrix::zeros(2, 3) {
    Ok(m) => m
    Err(msg) => abort("创建失败: \{msg}")
  }
  match m.det() {
    Ok(_) => abort("应当失败：非方阵没有行列式")
    Err(_) => ()
  }
}

test "越界访问返回 Err" {
  match m2x2().get(5, 5) {
    Ok(_) => abort("应当失败：越界访问")
    Err(_) => ()
  }
}

test "奇异矩阵求解返回 Err" {
  // [[1,2],[2,4]] 奇异（第二行是第一行的 2 倍）
  let a = match Matrix::from_array(2, 2, [1.0, 2.0, 2.0, 4.0]) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
  let b = match Matrix::from_array(2, 1, [1.0, 2.0]) {
    Ok(m) => m
    Err(msg) => abort("构造失败: \{msg}")
  }
  match a.solve(b) {
    Ok(_) => abort("应当失败：奇异矩阵")
    Err(_) => ()
  }
}

test "数据长度不匹配时在 MoonBit 侧就被拦下" {
  match Matrix::from_array(2, 2, [1.0, 2.0, 3.0]) {
    Ok(_) => abort("应当失败：长度不匹配")
    Err(_) => ()
  }
}
