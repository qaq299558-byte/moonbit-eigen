// examples/linreg/main.mbt —— 一元线性回归（正规方程）
//
// 数据由 y = 2x + 1 精确生成，因此正确结果是截距 1、斜率 2。
// 这个示例刻意选用**可手算核对**的数据：演示脚本的输出本身就是测试。
//
// ⚠️ 未编译验证：工具链就绪后需校对。

/// 从数组构造矩阵，失败直接终止（示例代码，不做优雅恢复）。
fn mat(rows : Int, cols : Int, data : Array[Double]) -> @eigen.Matrix {
  match @eigen.Matrix::from_array(rows, cols, data) {
    Ok(m) => m
    Err(msg) => {
      println("构造矩阵失败: \{msg}")
      abort("构造矩阵失败")
    }
  }
}

/// 取标量，失败直接终止。
fn scalar(m : @eigen.Matrix, i : Int, j : Int) -> Double {
  match m.get(i, j) {
    Ok(v) => v
    Err(msg) => {
      println("读取元素失败: \{msg}")
      abort("读取元素失败")
    }
  }
}

fn main {
  println("=== 一元线性回归（正规方程）===")
  println("真实模型: y = 2x + 1")
  println("")

  // 观测数据：x = 1..5，y = 2x + 1（无噪声，便于核对）
  let xs : Array[Double] = [1.0, 2.0, 3.0, 4.0, 5.0]
  let ys : Array[Double] = [3.0, 5.0, 7.0, 9.0, 11.0]

  // 设计矩阵 X 的第一列是全 1 的截距项
  let x = mat(5, 2, [
    1.0, 1.0,
    1.0, 2.0,
    1.0, 3.0,
    1.0, 4.0,
    1.0, 5.0,
  ])
  let y = mat(5, 1, ys)

  println("X = \{x.to_string()}")
  println("y = \{y.to_string()}")
  println("")

  // β = (XᵀX)⁻¹ Xᵀ y
  let xt = match x.transpose() {
    Ok(m) => m
    Err(msg) => {
      println("转置失败: \{msg}")
      return
    }
  }
  let xtx = match xt.mul(x) {
    Ok(m) => m
    Err(msg) => {
      println("XᵀX 失败: \{msg}")
      return
    }
  }
  let xty = match xt.mul(y) {
    Ok(m) => m
    Err(msg) => {
      println("Xᵀy 失败: \{msg}")
      return
    }
  }
  let beta = match xtx.solve(xty) {
    Ok(m) => m
    Err(msg) => {
      println("求解失败: \{msg}")
      return
    }
  }

  let intercept = scalar(beta, 0, 0)
  let slope = scalar(beta, 1, 0)

  println("拟合结果:")
  println("  截距 = \{intercept}    （期望 1）")
  println("  斜率 = \{slope}    （期望 2）")
  println("")

  // 用拟合出的参数做预测，验证闭环
  println("预测核对:")
  for i = 0; i < xs.length(); i = i + 1 {
    let predicted = intercept + slope * xs[i]
    println("  x=\{xs[i]}  真实 y=\{ys[i]}  预测 y=\{predicted}")
  }
  println("")

  // 残差平方和：无噪声数据下应为 0
  let resid = match xtx.mul(beta) {
    Ok(m) => m
    Err(msg) => {
      println("计算失败: \{msg}")
      return
    }
  }
  match resid.sub(xty) {
    Ok(r) => println("正规方程残差范数 = \{r.norm()}    （期望 0）")
    Err(msg) => println("计算残差失败: \{msg}")
  }
}
