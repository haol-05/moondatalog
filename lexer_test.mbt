// MoonDatalog —— 词法分析器测试
//
// 使用自定义的紧凑渲染函数将记号流转为可读文本，避免依赖
// Debug 输出格式，使断言稳定。

///|
fn render_kind(k : TokKind) -> String {
  match k {
    Ident(s) => "id(" + s + ")"
    IntLit(s) => "int(" + s + ")"
    FloatLit(s) => "float(" + s + ")"
    StrLit(s) => "str(" + s + ")"
    LParen => "("
    RParen => ")"
    Comma => ","
    Dot => "."
    Colon => ":"
    LBrace => "{"
    RBrace => "}"
    ColonDash => ":-"
    QuestionDash => "?-"
    Not => "not"
    Eq => "="
    Ne => "!="
    Lt => "<"
    Le => "<="
    Gt => ">"
    Ge => ">="
    Plus => "+"
    Minus => "-"
    Star => "*"
    Slash => "/"
    Percent => "%"
    Eof => "eof"
  }
}

///|
fn render_tokens(src : String) -> String {
  let toks = lex(src).unwrap()
  let b = StringBuilder::new()
  let mut first = true
  for t in toks.items {
    if first {
      first = false
    } else {
      b.write_string(" ")
    }
    b.write_string(render_kind(t.kind))
  }
  b.to_string()
}

///|
test "lexer 基本记号" {
  assert_eq(
    render_tokens("parent(alice, bob)."),
    "id(parent) ( id(alice) , id(bob) ) . eof",
  )
}

///|
test "lexer 数字与负数" {
  assert_eq(
    render_tokens("f(1, 2.5, -3, 1e3)."),
    "id(f) ( int(1) , float(2.5) , - int(3) , float(1e3) ) . eof",
  )
}

///|
test "lexer 字符串字面量与转义" {
  assert_eq(render_tokens("f(\"a\\\"b\\n\")."), "id(f) ( str(a\"b\n) ) . eof")
}

///|
test "lexer 运算符与关键字" {
  assert_eq(
    render_tokens("p(X) :- q(X), X != 5, X >= 1, not r(X)."),
    "id(p) ( id(X) ) :- id(q) ( id(X) ) , id(X) != int(5) , id(X) >= int(1) , not id(r) ( id(X) ) . eof",
  )
}

///|
test "lexer 注释与空白" {
  let src = "% 行注释\nparent(a, b). // 另一种注释\n/* 块注释 */ child(b, c).\n"
  assert_eq(
    render_tokens(src),
    "id(parent) ( id(a) , id(b) ) . id(child) ( id(b) , id(c) ) . eof",
  )
}

///|
test "lexer 位置跟踪" {
  let toks = lex("a.\nb(1).").unwrap()
  inspect(toks.items[1].pos, content="1:2")
  inspect(toks.items[3].pos, content="2:2")
  inspect(toks.items[4].pos, content="2:3")
}

///|
test "lexer 未闭合字符串报错" {
  let err = lex("f(\"abc).")
  assert_true(err is Err(_))
  match err {
    Err(e) =>
      assert_eq(
        e.to_string(),
        "词法错误 @ 1:3: 字符串字面量未闭合",
      )
    _ => abort("应当返回词法错误")
  }
}

///|
test "lexer 未知字符报错" {
  let err = lex("f(a) $ x.")
  match err {
    Err(e) =>
      assert_eq(e.to_string(), "词法错误 @ 1:6: 无法识别的字符: $")
    _ => abort("应当返回词法错误")
  }
}

///|
test "lexer 匿名变量" {
  assert_eq(render_tokens("edge(_, _)."), "id(edge) ( id(_) , id(_) ) . eof")
}
