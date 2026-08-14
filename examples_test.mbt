// MoonDatalog —— 示例程序验证
//
// 将 examples/ 下的示例程序作为黑盒测试运行，验证其行为与
// README 中描述一致。这样示例既可作为教学材料，也被测试锁定，
// 避免文档与实现脱节。

///|
fn run_ex(src : String) -> Result[EvalResult, DlError] {
  match parse(src) {
    Err(e) => Err(e)
    Ok(p) => evaluate(p)
  }
}

///|
fn answers_ex(result : EvalResult, qi : Int) -> Array[String] {
  let out : Array[String] = []
  for t in result.answers[qi] {
    out.push(t.to_string())
  }
  out
}

///|
test "示例：祖先传递闭包" {
  let src = "parent(alice, bob).\nparent(bob, carol).\nparent(carol, dave).\nparent(bob, eve).\nancestor(X, Y) :- parent(X, Y).\nancestor(X, Z) :- ancestor(X, Y), parent(Y, Z).\n?- ancestor(X, carol).\n?- ancestor(alice, Y).\n"
  let r = run_ex(src).unwrap()
  assert_eq(answers_ex(r, 0), ["(alice)", "(bob)"])
  assert_eq(answers_ex(r, 1), ["(bob)", "(carol)", "(dave)", "(eve)"])
}

///|
test "示例：图可达性与分层否定" {
  let src = "node(a).\nnode(b).\nnode(c).\nnode(d).\nnode(e).\nedge(a, b).\nedge(b, c).\nedge(c, d).\nreachable(X) :- node(X), edge(a, X).\nreachable(X) :- reachable(Y), edge(Y, X).\nunreachable(X) :- node(X), not reachable(X).\n?- unreachable(X).\n"
  let r = run_ex(src).unwrap()
  assert_eq(answers_ex(r, 0), ["(a)", "(e)"])
}

///|
test "示例：聚合（部门人数与最大值）" {
  let src = "employee(alice, eng).\nemployee(bob, eng).\nemployee(carol, sales).\nemployee(dave, sales).\nemployee(eve, sales).\ndept_size(D, N) :- employee(X, D), N = count : { X }.\nmax_dept(N) :- dept_size(_, S), N = max : { S }.\n?- dept_size(D, N).\n?- max_dept(N).\n"
  let r = run_ex(src).unwrap()
  assert_eq(answers_ex(r, 0), ["(eng, 2)", "(sales, 3)"])
  assert_eq(answers_ex(r, 1), ["(3)"])
}

///|
test "示例：数值聚合" {
  let src = "score(1, 10).\nscore(2, 20).\nscore(3, 30).\nscore(4, 40).\ntotal(T) :- score(_, S), T = sum : { S }.\nminimum(M) :- score(_, S), M = min : { S }.\nmaximum(M) :- score(_, S), M = max : { S }.\naverage(A) :- score(_, S), A = avg : { S }.\n?- total(T).\n?- minimum(M).\n?- maximum(M).\n?- average(A).\n"
  let r = run_ex(src).unwrap()
  assert_eq(answers_ex(r, 0), ["(100)"])
  assert_eq(answers_ex(r, 1), ["(10)"])
  assert_eq(answers_ex(r, 2), ["(40)"])
  assert_eq(answers_ex(r, 3), ["(25.0)"])
}
