// MoonDatalog —— 语法分析器测试

///|
/// 将程序渲染为紧凑文本，便于断言。
fn render_program(p : Program) -> String {
  let b = StringBuilder::new()
  for rule in p.rules {
    b.write_string(render_rule(rule))
    b.write_string("\n")
  }
  for q in p.queries {
    b.write_string("?- ")
    b.write_string(render_body(q.body))
    b.write_string("\n")
  }
  b.to_string()
}

///|
fn render_rule(r : Rule) -> String {
  let b = StringBuilder::new()
  b.write_string(render_atom(r.head))
  if !r.body.is_empty() {
    b.write_string(" :- ")
    b.write_string(render_body(r.body))
  }
  b.write_string(".")
  b.to_string()
}

///|
fn render_body(body : Array[BodyItem]) -> String {
  let parts : Array[String] = []
  for item in body {
    parts.push(render_item(item))
  }
  parts.join(", ")
}

///|
fn render_item(item : BodyItem) -> String {
  match item {
    Pos(a) => render_atom(a)
    Neg(a) => "not " + render_atom(a)
    Cmp(c) => render_cmp(c)
    Agg(agg) => render_agg(agg)
  }
}

///|
fn render_atom(a : Atom) -> String {
  let b = StringBuilder::new()
  b.write_string(a.pred)
  b.write_string("(")
  let args : Array[String] = []
  for t in a.args {
    args.push(render_term(t))
  }
  b.write_string(args.join(", "))
  b.write_string(")")
  b.to_string()
}

///|
fn render_term(t : Term) -> String {
  match t {
    Const(v) => v.to_string()
    Var(name) => name
    Neg(inner) => "-" + render_term(inner)
    Arith(op, l, r) =>
      "(" + render_term(l) + " " + render_op(op) + " " + render_term(r) + ")"
  }
}

///|
fn render_op(op : BinOp) -> String {
  match op {
    BinOp::Add => "+"
    BinOp::Sub => "-"
    BinOp::Mul => "*"
    BinOp::Div => "/"
    BinOp::Mod => "%"
  }
}

///|
fn render_cmp(c : Cmp) -> String {
  let op = match c.op {
    CmpOp::Eq => "="
    CmpOp::Ne => "!="
    CmpOp::Lt => "<"
    CmpOp::Le => "<="
    CmpOp::Gt => ">"
    CmpOp::Ge => ">="
  }
  render_term(c.lhs) + " " + op + " " + render_term(c.rhs)
}

///|
fn render_agg(agg : Aggregate) -> String {
  let func = match agg.func {
    AggFunc::Count => "count"
    AggFunc::Sum => "sum"
    AggFunc::Min => "min"
    AggFunc::Max => "max"
    AggFunc::Avg => "avg"
  }
  agg.agg_var + " = " + func + " : { " + agg.agg_vars.join(", ") + " }"
}

///|
test "parser 事实 / 规则 / 查询" {
  let src = "parent(alice, bob).\nancestor(X, Y) :- parent(X, Y).\nancestor(X, Z) :- ancestor(X, Y), parent(Y, Z).\n?- ancestor(X, carol).\n"
  let p = parse(src).unwrap()
  let text = render_program(p)
  inspect(
    text,
    content="parent(alice, bob).\nancestor(X, Y) :- parent(X, Y).\nancestor(X, Z) :- ancestor(X, Y), parent(Y, Z).\n?- ancestor(X, carol)\n",
  )
}

///|
test "parser 算术比较与赋值" {
  let src = "total(X, S) :- item(X, P), S = P * 2 + 1, S > 3."
  let p = parse(src).unwrap()
  let text = render_program(p)
  inspect(
    text,
    content="total(X, S) :- item(X, P), S = ((P * 2) + 1), S > 3.\n",
  )
}

///|
test "parser 否定" {
  let src = "safe(X) :- node(X), not danger(X)."
  let p = parse(src).unwrap()
  let text = render_program(p)
  inspect(text, content="safe(X) :- node(X), not danger(X).\n")
}

///|
test "parser 聚合" {
  let src = "count_pairs(N) :- edge(X, Y), N = count : { X, Y }."
  let p = parse(src).unwrap()
  let text = render_program(p)
  inspect(text, content="count_pairs(N) :- edge(X, Y), N = count : { X, Y }.\n")
}

///|
test "parser 字符串与数字常量" {
  let src = "rec(\"hello\", 42, 3.14, -7)."
  let p = parse(src).unwrap()
  let text = render_program(p)
  inspect(text, content="rec(\"hello\", 42, 3.14, -7).\n")
}

///|
test "parser 匿名变量展开为唯一变量" {
  let src = "edge(_, X, _)."
  let p = parse(src).unwrap()
  let text = render_program(p)
  inspect(text, content="edge(__anon0, X, __anon1).\n")
}

///|
test "parser 错误：谓词大写开头" {
  let err = parse("P(a).")
  match err {
    Err(e) =>
      assert_eq(
        e.to_string(),
        "语法错误 @ 1:1: 谓词名不能以大写字母开头: P",
      )
    _ => abort("应当返回语法错误")
  }
}

///|
test "parser 错误：缺少句号" {
  let err = parse("p(a)")
  match err {
    Err(e) =>
      assert_eq(
        e.to_string(),
        "语法错误 @ 1:5: 期望 ':-'、'.' 或 '?-'，但遇到 文件结尾",
      )
    _ => abort("应当返回语法错误")
  }
}

///|
test "parser 错误：算术出现在原子参数中" {
  let err = parse("p(X + 1).")
  match err {
    Err(e) =>
      assert_eq(e.to_string(), "语法错误 @ 1:5: 期望 ')'，但遇到 '+'")
    _ => abort("应当返回语法错误")
  }
}

///|
test "parser 空程序" {
  let p = parse("").unwrap()
  assert_eq(p.rules.length(), 0)
  assert_eq(p.queries.length(), 0)
}
