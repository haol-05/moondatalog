// MoonDatalog —— 形式化验证函数的运行时测试
//
// 这些函数同时通过 `moon prove` 机器校验（逻辑正确性）
// 与运行时测试（实际执行行为），双重保证。

///|
test "verified clamp 夹取" {
  assert_eq(clamp(5, 0, 10), 5)
  assert_eq(clamp(-3, 0, 10), 0)
  assert_eq(clamp(15, 0, 10), 10)
  assert_eq(clamp(0, 0, 10), 0)
  assert_eq(clamp(10, 0, 10), 10)
}

///|
test "verified bounded_sum 有界求和" {
  let xs = FixedArray::from_array([1, 2, 3, 4])
  assert_eq(bounded_sum(xs, 0, 10), 10)
  let ys = FixedArray::from_array([-5, 5, -5, 5])
  assert_eq(bounded_sum(ys, -5, 5), 0)
  let empty = FixedArray::from_array([])
  assert_eq(bounded_sum(empty, 0, 100), 0)
}

///|
test "verified index_of_max 最大值下标" {
  let xs = FixedArray::from_array([3, 9, 2, 7])
  assert_eq(index_of_max(xs), 1)
  let ys = FixedArray::from_array([5, 5, 5])
  assert_eq(index_of_max(ys), 0)
  let zs = FixedArray::from_array([-1, -3, -2])
  assert_eq(index_of_max(zs), 0)
}
