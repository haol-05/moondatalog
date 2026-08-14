// MoonDatalog —— 抽象语法树（AST）
//
// 语法模型遵循经典 Datalog 并做少量实用扩展：
//   - 事实：`parent(alice, bob).`
//   - 规则：`ancestor(X, Y) :- parent(X, Y).`
//   - 查询：`?- ancestor(X, carol).`
//   - 算术比较 / 赋值：`X < Y`、`X = Y + 1`
//   - 分层否定：`not friend(X, Y)`
//   - 聚合（Soufflé 风格）：`N = count : { X }`

///|
/// 源码位置（行 / 列，均从 1 起）。
pub struct Pos {
  line : Int
  col : Int
} derive(Eq, @debug.Debug)

///|
pub impl Show for Pos with fn to_string(self : Pos) -> String {
  "\{self.line}:\{self.col}"
}

///|
/// 算术二元运算符。
pub enum BinOp {
  Add
  Sub
  Mul
  Div
  Mod
} derive(Eq, @debug.Debug)

///|
/// 比较 / 赋值运算符。
pub enum CmpOp {
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
} derive(Eq, @debug.Debug)

///|
/// 聚合函数。
pub enum AggFunc {
  Count
  Sum
  Min
  Max
  Avg
} derive(Eq, @debug.Debug)

///|
/// 项（原子参数）：常量、变量、一元负号或算术表达式。
pub enum Term {
  /// 常量字面量
  Const(Value)
  /// 变量（`_` 匿名变量在解析时被替换为唯一生成的名字）
  Var(String)
  /// 一元负号 `-t`
  Neg(Term)
  /// 算术表达式 `lhs op rhs`
  Arith(BinOp, Term, Term)
} derive(Eq, @debug.Debug)

///|
/// 是否为变量名：`_` 或大写字母开头的标识符。
pub fn is_variable_name(s : String) -> Bool {
  if s == "_" {
    return true
  }
  let mut first_char : Char? = None
  for c in s.iter() {
    first_char = Some(c)
    break
  }
  match first_char {
    Some(c) => c.is_ascii_uppercase()
    None => false
  }
}

///|
/// 规则体中的一项。
pub enum BodyItem {
  /// 正原子
  Pos(Atom)
  /// 否定原子 `not p(...)`
  Neg(Atom)
  /// 比较 / 赋值约束
  Cmp(Cmp)
  /// 聚合项 `N = func : { ... }`
  Agg(Aggregate)
} derive(Eq, @debug.Debug)

///|
/// 谓词原子 `pred(t1, ..., tn)`。
pub struct Atom {
  pred : String
  args : Array[Term]
  pos : Pos
} derive(Eq, @debug.Debug)

///|
/// 比较 / 赋值约束。
pub struct Cmp {
  op : CmpOp
  lhs : Term
  rhs : Term
  pos : Pos
} derive(Eq, @debug.Debug)

///|
/// 聚合项：`agg_var = func : { agg_vars... }`。
///
/// 语义与 Soufflé 一致：以规则体中其余变量为分组键，
/// 组内对 `agg_vars` 对应的取值集合计算聚合函数，结果绑定到 `agg_var`。
pub struct Aggregate {
  agg_var : String
  func : AggFunc
  agg_vars : Array[String]
  pos : Pos
} derive(Eq, @debug.Debug)

///|
/// 一条规则：`head :- body.`（事实为 `body` 为空）。
pub struct Rule {
  head : Atom
  body : Array[BodyItem]
  pos : Pos
} derive(Eq, @debug.Debug)

///|
/// 一个查询：`?- body.`
pub struct Query {
  body : Array[BodyItem]
  pos : Pos
} derive(Eq, @debug.Debug)

///|
/// 完整程序：规则（含事实）与查询。
pub struct Program {
  rules : Array[Rule]
  queries : Array[Query]
} derive(Eq, @debug.Debug)

///|
/// 引擎错误。
pub enum DlError {
  /// 词法错误
  LexError(Pos, String)
  /// 语法错误
  ParseError(Pos, String)
  /// 语义错误（未定义谓词、元数不符、不安全规则、不可分层否定等）
  SemanticError(String)
  /// 求值错误（除零、聚合用法非法等）
  EvalError(String)
} derive(Eq, @debug.Debug)

///|
pub fn DlError::to_string(self : DlError) -> String {
  match self {
    LexError(pos, msg) => "词法错误 @ \{pos}: \{msg}"
    ParseError(pos, msg) => "语法错误 @ \{pos}: \{msg}"
    SemanticError(msg) => "语义错误: \{msg}"
    EvalError(msg) => "求值错误: \{msg}"
  }
}
