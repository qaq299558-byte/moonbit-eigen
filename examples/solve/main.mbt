// examples/solve/main.mbt —— 解线性方程组
//
// 用途（对应官方验收第 3 条"可运行示例"）：
//   · 在一屏之内展示这个绑定能做什么
//   · 演示错误处理路径确实可用（故意跑一个奇异矩阵）
//
// ⚠️ 未编译验证：工具链就绪后需校对。

/// 打印结果或错误，避免到处写 match。
fn show(label : String, result : Result[@eigen.Matrix, String]) -> Unit {
  match result {
    Ok(m) => {
      println("\{label}:")
      println(m.to_string())
    }
    Err(msg) => println("\{label} 失败: \{msg}")
  }
}

fn main {
  println("=== 解线性方程组 Ax = b ===")

  // 2x +  y = 3
  //  x + 3y = 5     =>  x = 0.8, y = 1.4
  let a = match @eigen.Matrix::from_array(2, 2, [2.0, 1.0, 1.0, 3.0]) {
    Ok(m) => m
    Err(msg) => {
      println("构造 A 失败: \{msg}")
      return
    }
  }
  let b = match @eigen.Matrix::from_array(2, 1, [3.0, 5.0]) {
    Ok(m) => m
    Err(msg) => {
      println("构造 b 失败: \{msg}")
      return
    }
  }

  println("A = \{a.to_string()}")
  println("b = \{b.to_string()}")

  match a.det() {
    Ok(d) => println("det(A) = \{d}")
    Err(msg) => println("det(A) 失败: \{msg}")
  }

  show("x = A^-1 b", a.solve(b))

  println("")
  println("=== 错误路径演示 ===")

  // 奇异矩阵：第二行是第一行的 2 倍，无唯一解。
  let singular = match @eigen.Matrix::from_array(2, 2, [1.0, 2.0, 2.0, 4.0]) {
    Ok(m) => m
    Err(msg) => {
      println("构造失败: \{msg}")
      return
    }
  }
  show("奇异矩阵求解（预期失败）", singular.solve(b))

  // 维度不匹配：3x3 加 2x2
  let three = match @eigen.Matrix::zeros(3, 3) {
    Ok(m) => m
    Err(msg) => {
      println("构造失败: \{msg}")
      return
    }
  }
  show("维度不匹配的加法（预期失败）", a.add(three))
}
