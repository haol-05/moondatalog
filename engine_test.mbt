// MoonDatalog —— 求值引擎测试
//
// 覆盖：传递闭包、算术、否定（分层）、聚合、错误处理等。

///|
/// 解析并求值一个程序。
fn run(src : String) -> Result[EvalResult, DlError] {
  match parse(src) {
    Err(e) => Err(e)
    Ok(p) => evaluate(p)
  }
}

///|
/// 第 i 个查询的答案，渲染为可读字符串（元组按字典序输出）。
fn answers(result : EvalResult, qi : Int) -> Array[String] {
  let out : Array[String] = []
  for t in result.answers[qi] {
    out.push(t.to_string())
  }
  out
}

///|
/// 求某个关系的全部元组（排序后）。
fn relation_strings(result : EvalResult, pred : String) -> Array[String] {
  let rel = result.relations[pred]
  let out : Array[String] = []
  for t in rel.iter() {
    out.push(t.to_string())
  }
  out.sort_by(fn(a, b) { a.lexical_compare(b) })
  out
}

///|
test "engine 传递闭包（ancestor）" {
  let src = "parent(alice, bob). parent(bob, carol). parent(carol, dave).\nancestor(X, Y) :- parent(X, Y).\nancestor(X, Z) :- ancestor(X, Y), parent(Y, Z).\n?- ancestor(X, carol).\n?- ancestor(alice, Y).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(alice)", "(bob)"])
  assert_eq(answers(r, 1), ["(bob)", "(carol)", "(dave)"])
  // 全部 ancestor 元组
  assert_eq(relation_strings(r, "ancestor"), [
    "(alice, bob)", "(alice, carol)", "(alice, dave)", "(bob, carol)", "(bob, dave)",
    "(carol, dave)",
  ])
}

///|
test "engine 传递闭包（数值图）" {
  let src = "edge(1, 2). edge(2, 3). edge(3, 4).\npath(X, Y) :- edge(X, Y).\npath(X, Z) :- path(X, Y), edge(Y, Z).\n?- path(1, X).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(2)", "(3)", "(4)"])
  assert_eq(relation_strings(r, "path").length(), 6)
}

///|
test "engine 兄弟关系（比较 + 不等式）" {
  let src = "parent(a, b). parent(b, c). parent(a, d). parent(d, e).\nsib(X, Y) :- parent(P, X), parent(P, Y), X != Y.\n?- sib(X, Y).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(b, d)", "(d, b)"])
}

///|
test "engine 算术与比较" {
  let src = "price(item1, 10). price(item2, 25). price(item3, 30).\nexpensive(X) :- price(X, P), P >= 25.\ndiscount(X, D) :- price(X, P), D = P * 90 / 100.\n?- expensive(X).\n?- discount(X, D).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(item2)", "(item3)"])
  assert_eq(answers(r, 1), ["(item1, 9)", "(item2, 22)", "(item3, 27)"])
}

///|
test "engine 分层否定（不可达节点）" {
  let src = "node(a). node(b). node(c). node(d).\nedge(a, b). edge(b, c). edge(c, d).\nreachable(X) :- node(X), edge(a, X).\nreachable(X) :- reachable(Y), edge(Y, X).\nunreachable(X) :- node(X), not reachable(X).\n?- unreachable(X).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(a)"])
}

///|
test "engine 聚合：出度" {
  let src = "edge(a, b). edge(a, c). edge(b, c). edge(c, d).\nout_degree(X, N) :- edge(X, Y), N = count : { Y }.\n?- out_degree(X, N).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(a, 2)", "(b, 1)", "(c, 1)"])
}

///|
test "engine 聚合：全局计数与求和" {
  let src = "link(1, 2). link(2, 3). link(3, 4).\ncount_pairs(N) :- link(X, Y), N = count : { X, Y }.\nout_sum(X, S) :- link(X, Y), S = sum : { Y }.\n?- count_pairs(N).\n?- out_sum(X, S).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(3)"])
  assert_eq(answers(r, 1), ["(1, 2)", "(2, 3)", "(3, 4)"])
}

///|
test "engine 聚合：min / max / avg（全局）" {
  let src = "score(alice, 85). score(bob, 92). score(carol, 78).\nbest(N) :- score(_, S), N = max : { S }.\nworst(N) :- score(_, S), N = min : { S }.\n?- best(N).\n?- worst(N).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(92)"])
  assert_eq(answers(r, 1), ["(78)"])
}

///|
test "engine 字符串与浮点数" {
  let src = "record(\"alice\", 3.5). record(\"bob\", 2.0).\nheavy(X) :- record(X, W), W > 3.0.\n?- heavy(X).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(\"alice\")"])
}

///|
test "engine 数值跨类型相等" {
  let src = "n(3).\np(X) :- n(X), X = 3.0.\n?- p(X).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(3)"])
}

///|
test "engine 事实去重" {
  let src = "p(1). p(1). p(2).\n?- p(X).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(1)", "(2)"])
}

///|
test "engine 查询投影去重排序" {
  let src = "person(a). person(b). person(c).\nfriend(a, b). friend(b, c).\n?- person(X), friend(X, Y), person(Y), not friend(Y, X).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(a, b)", "(b, c)"])
}

///|
test "engine 匿名变量查询" {
  let src = "node(a). node(b). edge(a, b).\n?- edge(_, _).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(a, b)"])
}

///|
test "engine 无变量查询为布尔判定" {
  let src = "edge(a, b).\n?- edge(a, b).\n?- edge(b, a).\n"
  let r = run(src).unwrap()
  assert_eq(r.answers[0].length(), 1)
  assert_eq(r.answers[1].length(), 0)
}

///|
test "engine 规则可复用低层关系（两层推导）" {
  let src = "base(a, b). base(b, c).\nfirst(X, Y) :- base(X, Y).\nsecond(X, Z) :- first(X, Y), first(Y, Z).\n?- second(X, Z).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0), ["(a, c)"])
}

///|
test "engine 错误：不可分层否定" {
  let src = "q(a).\np(X) :- q(X), not p(X).\n"
  let err = run(src)
  match err {
    Err(e) => assert_true(e.to_string().contains("不可分层"))
    _ => abort("应当返回分层错误")
  }
}

///|
test "engine 错误：不安全规则" {
  let src = "q(a).\np(X) :- q(Y).\n"
  let err = run(src)
  match err {
    Err(e) => assert_true(e.to_string().contains("不安全"))
    _ => abort("应当返回安全性错误")
  }
}

///|
test "engine 错误：元数不一致" {
  let src = "p(a).\np(a, b).\n"
  let err = run(src)
  match err {
    Err(e) => assert_true(e.to_string().contains("元数不一致"))
    _ => abort("应当返回元数错误")
  }
}

///|
test "engine 错误：未定义谓词" {
  let src = "p(X) :- q(X).\n"
  let err = run(src)
  match err {
    Err(e) => assert_true(e.to_string().contains("未定义谓词"))
    _ => abort("应当返回未定义谓词错误")
  }
}

///|
test "engine 错误：除零" {
  let src = "n(10).\nq(5).\np(X) :- n(N), q(X), X = N / (N - N).\n?- p(X).\n"
  let err = run(src)
  match err {
    Err(e) => assert_true(e.to_string().contains("除零"))
    _ => abort("应当返回除零错误")
  }
}

///|
test "engine 错误：聚合递归" {
  let src = "edge(a, b).\ncnt(X, N) :- cnt(Y, _), edge(X, Y), N = count : { Y }.\n"
  let err = run(src)
  match err {
    Err(e) => assert_true(e.to_string().contains("递归"))
    _ => abort("应当返回聚合递归错误")
  }
}

///|
test "engine 错误：聚合结果变量未出现在头部" {
  let src = "edge(a, b).\np(X) :- edge(X, Y), N = count : { Y }.\n"
  let err = run(src)
  match err {
    Err(e) => assert_true(e.to_string().contains("聚合结果变量"))
    _ => abort("应当返回聚合用法错误")
  }
}

///|
test "engine 错误：sum 多列聚合" {
  let src = "edge(a, b).\np(N) :- edge(X, Y), N = sum : { X, Y }.\n"
  let err = run(src)
  match err {
    Err(e) => assert_true(e.to_string().contains("只接受一个聚合参数"))
    _ => abort("应当返回聚合参数错误")
  }
}

///|
test "engine 复杂程序：无冲突图着色" {
  let src = "node(a). node(b). node(c).\nedge(a, b). edge(b, c). edge(a, c).\ncolor(a, red). color(b, green). color(c, blue).\nconflict(X, Y) :- edge(X, Y), color(X, C), color(Y, C).\n?- conflict(X, Y).\n"
  let r = run(src).unwrap()
  assert_eq(answers(r, 0).length(), 0)
}
