// MoonDatalog —— 可读渲染（把 AST 转回 Datalog 文本）
//
// 供 CLI 与测试复用，保持输出与输入语法一致的显示风格。

///|
/// 渲染一条查询为可读文本。
pub fn render_query(q : Query) -> String {
  let b = StringBuilder::new()
  let mut first = true
  for item in q.body {
    if first {
      first = false
    } else {
      b.write_string(", ")
    }
    b.write_string(render_body_item(item))
  }
  b.to_string()
}

///|
/// 渲染一条规则（含事实）为可读文本。
pub fn render_rule(r : Rule) -> String {
  let b = StringBuilder::new()
  b.write_string(render_atom(r.head))
  if !r.body.is_empty() {
    b.write_string(" :- ")
    let mut first = true
    for item in r.body {
      if first {
        first = false
      } else {
        b.write_string(", ")
      }
      b.write_string(render_body_item(item))
    }
  }
  b.write_string(".")
  b.to_string()
}

///|
/// 渲染一个规则体项。
pub fn render_body_item(item : BodyItem) -> String {
  match item {
    Pos(a) => render_atom(a)
    Neg(a) => "not " + render_atom(a)
    Cmp(c) => render_cmp(c)
    Agg(agg) => render_agg(agg)
  }
}

///|
/// 渲染一个原子。
pub fn render_atom(a : Atom) -> String {
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
/// 渲染一个项。
pub fn render_term(t : Term) -> String {
  match t {
    Const(v) => v.to_string()
    Var(name) => name
    Neg(inner) => "-" + render_term(inner)
    Arith(op, l, r) =>
      "(" + render_term(l) + " " + render_binop(op) + " " + render_term(r) + ")"
  }
}

///|
fn render_binop(op : BinOp) -> String {
  match op {
    BinOp::Add => "+"
    BinOp::Sub => "-"
    BinOp::Mul => "*"
    BinOp::Div => "/"
    BinOp::Mod => "%"
  }
}

///|
/// 渲染一个比较约束。
pub fn render_cmp(c : Cmp) -> String {
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
/// 渲染一个聚合项。
pub fn render_agg(agg : Aggregate) -> String {
  let func = match agg.func {
    AggFunc::Count => "count"
    AggFunc::Sum => "sum"
    AggFunc::Min => "min"
    AggFunc::Max => "max"
    AggFunc::Avg => "avg"
  }
  agg.agg_var + " = " + func + " : { " + agg.agg_vars.join(", ") + " }"
}
