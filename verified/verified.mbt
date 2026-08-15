// MoonDatalog —— 形式化验证：程序侧函数（.mbt）
//
// 本文件演示 MoonBit 的形式化验证能力（`moon prove` 子命令）：
// 为三个纯函数附加逻辑契约（前置 / 后置条件、循环不变量），
// 并借助 SMT 求解器机器校验其正确性。
// 逻辑规范定义在同目录 verified.mbtp 中。

///|
/// 将 x 夹在 [lo, hi] 之间。
///
/// 形式化保证：给定 `valid_bounds(lo, hi)`，返回值必在 [lo, hi] 内。
pub fn clamp(x : Int, lo : Int, hi : Int) -> Int where {
  proof_require: valid_bounds(lo, hi),
  proof_ensure: result => clamped(lo, hi, result),
} {
  if x < lo {
    lo
  } else if x > hi {
    hi
  } else {
    x
  }
}

///|
/// 计算数组元素之和。
///
/// 形式化保证：若每个元素都在 [lo, hi] 内（`in_range`），
/// 则总和被夹在 lo*len 与 hi*len 之间（`sum_bounded`）。
pub fn bounded_sum(xs : FixedArray[Int], lo : Int, hi : Int) -> Int where {
  proof_require: in_range(xs, lo, hi),
  proof_ensure: result => sum_bounded(xs, lo, hi, result),
} {
  for i = 0, sum = 0; i < xs.length(); {
    let new_sum = sum + xs[i]
    continue i + 1, new_sum
  } nobreak {
    sum
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: lo * i <= sum,
    proof_invariant: sum <= hi * i,
    proof_reasoning: (
      #| 处理完前 i 个元素后，sum 是前缀总和，且夹在 lo*i 与 hi*i 之间。
      #| 初始：i = 0、sum = 0，两个不等式恰等号成立。
      #| 保持：前置条件保证 lo <= xs[i] <= hi，加入后
      #|   lo*i + lo <= sum + xs[i] <= hi*i + hi，即 i+1 时的不变量。
      #| 终止：i 每步递增，度量 xs.length() - i 严格递减。
      #| 退出：i = xs.length()，前缀界即整体和的界。
    ),
  }
}

///|
/// 返回数组中最大值元素的下标。
///
/// 形式化保证：给定数组非空（`nonempty`），返回的下标指向全局最大值
/// （`is_max_index`）。
pub fn index_of_max(xs : FixedArray[Int]) -> Int where {
  proof_require: nonempty(xs),
  proof_ensure: result => is_max_index(xs, result),
} {
  for i = 1, best = 0; i < xs.length(); {
    let new_best = if xs[i] > xs[best] {
      i
    } else {
      best
    }
    continue i + 1, new_best
  } nobreak {
    best
  } where {
    proof_invariant: 1 <= i,
    proof_invariant: i <= xs.length(),
    proof_invariant: 0 <= best,
    proof_invariant: best < i,
    proof_invariant: max_in_prefix(xs, best, i),
    proof_reasoning: (
      #| best 始终是已处理前缀 xs[0..i) 中最大元素的下标。
      #| 初始：前缀只有一个元素，best = 0 平凡成立。
      #| 保持：考察 xs[i] 时，若 xs[i] > xs[best] 则新元素成为新最大值
      #|   下标；否则原 witness 依旧支配扩大的前缀。
      #| 终止：i 每步递增，度量 xs.length() - i 严格递减。
      #| 退出：i = xs.length()，max_in_prefix 即「best 是全局最大下标」。
    ),
  }
}
