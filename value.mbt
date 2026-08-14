// MoonDatalog —— 值类型（Value）
//
// Datalog 程序中的基本数据值。经典 Datalog 只有符号常量，
// 本引擎额外支持字符串、整数与浮点数，以覆盖更广泛的
// 数据处理与查询场景（图分析、配置校验、数据管道等）。

///|
/// 一个 Datalog 数据值。
///
/// 四种构造子按全序排列：符号常量 < 字符串 < 整数 < 浮点数。
/// 该顺序保证元组与关系具备确定的字典序，便于排序与去重。
pub enum Value {
  /// 符号常量，如 `alice`（由小写标识符构成）
  Sym(String)
  /// 字符串常量，如 `"hello"`（带引号字面量）
  Str(String)
  /// 64 位有符号整数，如 `42`、`-7`
  Int(Int64)
  /// IEEE-754 双精度浮点数，如 `3.14`、`1e-9`
  Float(Double)
} derive(Eq, Hash, Compare, @debug.Debug)

///|
/// 将值渲染为 Datalog 字面量文本：
/// 符号原样输出，字符串加引号并转义，整数十进制，浮点数保留小数形式。
pub impl Show for Value with fn to_string(self : Value) -> String {
  match self {
    Sym(s) => s
    Str(s) => quote_string(s)
    Int(i) => i.to_string()
    Float(f) => format_double(f)
  }
}

///|
/// 为字符串字面量加引号并转义 `"` 与 `\`。
fn quote_string(s : String) -> String {
  let b = StringBuilder::new()
  b.write_char('"')
  for c in s.iter() {
    match c {
      '"' => b.write_string("\\\"")
      '\\' => b.write_string("\\\\")
      '\n' => b.write_string("\\n")
      '\r' => b.write_string("\\r")
      '\t' => b.write_string("\\t")
      _ => b.write_char(c)
    }
  }
  b.write_char('"')
  b.to_string()
}

///|
/// 浮点数的确定化输出：整数型浮点输出为 `3.0` 形式，避免与整数歧义；
/// 其余按核心库默认表示（含指数或小数）。
fn format_double(f : Double) -> String {
  if f.is_nan() || f.is_inf() {
    return f.to_string()
  }
  let s = f.to_string()
  if s.contains_char('.') || s.contains_char('e') || s.contains_char('E') {
    return s
  }
  s + ".0"
}

///|
/// 解析一个十进制整数字面量（可为负）。失败返回 `None`。
pub fn parse_int(s : String) -> Value? {
  let parsed : Int64? = Some(@string.parse_int64(s)) catch { _ => None }
  match parsed {
    Some(i) => Some(Int(i))
    None => None
  }
}

///|
/// 解析一个十进制浮点字面量（可为负、可含指数）。失败返回 `None`。
pub fn parse_float(s : String) -> Value? {
  let parsed : Double? = Some(@string.parse_double(s)) catch { _ => None }
  match parsed {
    Some(f) => Some(Float(f))
    None => None
  }
}

///|
/// 将任意字面量文本（数字或标识符）规约为 Value：
/// 可解析为整数则取整数，否则可解析为浮点则取浮点，否则视为符号常量。
pub fn from_literal(s : String) -> Value {
  match parse_int(s) {
    Some(v) => v
    None =>
      match parse_float(s) {
        Some(v) => v
        None => Sym(s)
      }
  }
}

///|
/// 值的确定化全序比较：
///   - 同类数值按数值比较（Int/Float 混合按浮点）；
///   - 符号 / 字符串按字典序（`lexical_compare`，注意非 `String::compare`）；
///   - 跨类别按 符号 < 字符串 < 整数 < 浮点 的固定序。
pub fn compare_values(a : Value, b : Value) -> Int {
  match (a, b) {
    (Int(x), Int(y)) => x.compare(y)
    (Float(x), Float(y)) => x.compare(y)
    (Int(x), Float(y)) => x.to_double().compare(y)
    (Float(x), Int(y)) => x.compare(y.to_double())
    (Sym(x), Sym(y)) => x.lexical_compare(y)
    (Str(x), Str(y)) => x.lexical_compare(y)
    (Sym(_), _) => -1
    (_, Sym(_)) => 1
    (Str(_), _) => -1
    (_, Str(_)) => 1
  }
}

///|
/// 构造符号常量（供外部使用，等价于公开枚举构造子）。
pub fn sym(s : String) -> Value {
  Sym(s)
}

///|
/// 构造字符串常量。
pub fn str_const(s : String) -> Value {
  Str(s)
}

///|
/// 构造整数常量。
pub fn int_const(i : Int64) -> Value {
  Int(i)
}

///|
/// 构造浮点常量。
pub fn float_const(f : Double) -> Value {
  Float(f)
}
