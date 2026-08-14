// MoonDatalog —— 词法分析器（Lexer）
//
// 将 Datalog 源码文本切分为记号流。支持的记号：
//   - 标识符（谓词 / 变量 / 符号常量，`_` 为匿名变量）
//   - 整数与浮点字面量（浮点必须为 `digits.digits`，避免与句号冲突）
//   - 字符串字面量（支持 `\"` `\\` `\n` `\r` `\t` 转义）
//   - 标点与运算符：`(` `)` `,` `.` `:` `{` `}` `:-` `?-`
//     `=` `!=` `<` `<=` `>` `>=` `+` `-` `*` `/` `%`
//   - 关键字：`not`
//   - 注释：`%` 行注释、`//` 行注释、`/* ... */` 块注释

///|
/// 记号类别。
pub enum TokKind {
  /// 标识符（谓词 / 变量 / 符号常量），文本为原名
  Ident(String)
  /// 整数字面量，文本为原始数字串（不含符号）
  IntLit(String)
  /// 浮点字面量，文本为原始数字串（不含符号）
  FloatLit(String)
  /// 字符串字面量，已解码转义
  StrLit(String)
  LParen
  RParen
  Comma
  Dot
  Colon
  LBrace
  RBrace
  /// `:-`
  ColonDash
  /// `?-`
  QuestionDash
  /// `not`
  Not
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
  Plus
  Minus
  Star
  Slash
  Percent
  Eof
} derive(Eq, @debug.Debug)

///|
/// 一个带位置的记号。
pub struct Token {
  kind : TokKind
  pos : Pos
} derive(Eq, @debug.Debug)

///|
/// 记号流。
pub struct Tokens {
  items : Array[Token]
}

///|
pub fn Tokens::length(self : Tokens) -> Int {
  self.items.length()
}

///|
pub fn Tokens::get(self : Tokens, i : Int) -> Token {
  self.items[i]
}

///|
/// 词法分析：将源码切分为记号。失败时返回带位置的词法错误。
pub fn lex(src : String) -> Result[Tokens, DlError] {
  let chars : Array[Char] = []
  let offsets : Array[Int] = []
  for offset, c in src.iter2() {
    chars.push(c)
    offsets.push(offset)
  }
  let src_len = src.length()
  let mut cursor = 0
  let mut line = 1
  let mut col = 1
  let tokens : Array[Token] = []

  let peek_char = fn() -> Char? {
    if cursor < chars.length() {
      return Some(chars[cursor])
    }
    None
  }

  let peek2_char = fn() -> Char? {
    if cursor + 1 < chars.length() {
      return Some(chars[cursor + 1])
    }
    None
  }

  let cur_pos = fn() -> Pos { { line, col } }

  // 前进一个字符并维护行列计数
  let advance = fn() -> Unit {
    if cursor >= chars.length() {
      return
    }
    let c = chars[cursor]
    cursor = cursor + 1
    if c == '\n' {
      line = line + 1
      col = 1
    } else {
      col = col + 1
    }
  }

  // 按字节区间切片源文本（用于标识符与数字）
  let slice_bytes = fn(start : Int, end : Int) -> String {
    let byte_start = offsets[start]
    let byte_end = if end < offsets.length() { offsets[end] } else { src_len }
    src[byte_start:byte_end].to_owned()
  }

  // 跳过空白与注释
  let skip_trivia = fn() -> Unit {
    let mut go = true
    while go {
      go = false
      match peek_char() {
        Some(c) =>
          if c == ' ' || c == '\t' || c == '\r' || c == '\n' {
            advance()
            go = true
          } else if c == '%' {
            // 行注释到行尾
            while (match peek_char() {
                    Some(c1) => c1 != '\n'
                    None => false
                  }) {
              advance()
            }
            go = true
          } else if c == '/' && peek2_char() == Some('/') {
            advance()
            advance()
            while (match peek_char() {
                    Some(c1) => c1 != '\n'
                    None => false
                  }) {
              advance()
            }
            go = true
          } else if c == '/' && peek2_char() == Some('*') {
            advance()
            advance()
            let mut closed = false
            while cursor < chars.length() {
              if chars[cursor] == '*' &&
                cursor + 1 < chars.length() &&
                chars[cursor + 1] == '/' {
                advance()
                advance()
                closed = true
                break
              }
              advance()
            }
            if !closed {
              return // 未闭合块注释：由后续解析报错，这里静默忽略
            }
            go = true
          }
        None => ()
      }
    }
  }

  while cursor < chars.length() {
    skip_trivia()
    if cursor >= chars.length() {
      break
    }
    let pos = cur_pos()
    let c = chars[cursor]
    if c.is_ascii_alphabetic() || c == '_' {
      let start = cursor
      while cursor < chars.length() {
        let c1 = chars[cursor]
        if c1.is_ascii_alphabetic() || c1.is_ascii_digit() || c1 == '_' {
          advance()
        } else {
          break
        }
      }
      let text = slice_bytes(start, cursor)
      if text == "not" {
        tokens.push({ kind: Not, pos })
      } else {
        tokens.push({ kind: Ident(text), pos })
      }
    } else if c.is_ascii_digit() {
      let start = cursor
      while cursor < chars.length() && chars[cursor].is_ascii_digit() {
        advance()
      }
      let mut is_float = false
      // 小数点后必须跟数字（避免与句号冲突）
      if cursor + 1 < chars.length() &&
        chars[cursor] == '.' &&
        chars[cursor + 1].is_ascii_digit() {
        is_float = true
        advance() // '.'
        while cursor < chars.length() && chars[cursor].is_ascii_digit() {
          advance()
        }
      }
      // 指数部分
      if cursor < chars.length() &&
        (chars[cursor] == 'e' || chars[cursor] == 'E') {
        let mut lookahead = cursor + 1
        if lookahead < chars.length() &&
          (chars[lookahead] == '+' || chars[lookahead] == '-') {
          lookahead = lookahead + 1
        }
        if lookahead < chars.length() && chars[lookahead].is_ascii_digit() {
          is_float = true
          advance() // e/E
          if cursor < chars.length() &&
            (chars[cursor] == '+' || chars[cursor] == '-') {
            advance()
          }
          while cursor < chars.length() && chars[cursor].is_ascii_digit() {
            advance()
          }
        }
      }
      let text = slice_bytes(start, cursor)
      if is_float {
        tokens.push({ kind: FloatLit(text), pos })
      } else {
        tokens.push({ kind: IntLit(text), pos })
      }
    } else if c == '"' {
      let content_builder = StringBuilder::new()
      advance() // 开引号
      let mut closed = false
      while cursor < chars.length() {
        let c1 = chars[cursor]
        if c1 == '"' {
          advance()
          closed = true
          break
        } else if c1 == '\\' {
          advance()
          if cursor >= chars.length() {
            break
          }
          let esc = chars[cursor]
          match esc {
            'n' => content_builder.write_char('\n')
            'r' => content_builder.write_char('\r')
            't' => content_builder.write_char('\t')
            '"' => content_builder.write_char('"')
            '\\' => content_builder.write_char('\\')
            _ => {
              content_builder.write_char('\\')
              content_builder.write_char(esc)
            }
          }
          advance()
        } else {
          content_builder.write_char(c1)
          advance()
        }
      }
      if !closed {
        return Err(LexError(pos, "字符串字面量未闭合"))
      }
      tokens.push({ kind: StrLit(content_builder.to_string()), pos })
    } else {
      // 运算符与标点
      match c {
        '(' => {
          advance()
          tokens.push({ kind: LParen, pos })
        }
        ')' => {
          advance()
          tokens.push({ kind: RParen, pos })
        }
        ',' => {
          advance()
          tokens.push({ kind: Comma, pos })
        }
        '.' => {
          advance()
          tokens.push({ kind: Dot, pos })
        }
        ':' =>
          if peek2_char() == Some('-') {
            advance()
            advance()
            tokens.push({ kind: ColonDash, pos })
          } else {
            advance()
            tokens.push({ kind: Colon, pos })
          }
        '?' =>
          if peek2_char() == Some('-') {
            advance()
            advance()
            tokens.push({ kind: QuestionDash, pos })
          } else {
            return Err(LexError(pos, "意外的字符 '?'"))
          }
        '{' => {
          advance()
          tokens.push({ kind: LBrace, pos })
        }
        '}' => {
          advance()
          tokens.push({ kind: RBrace, pos })
        }
        '=' => {
          advance()
          tokens.push({ kind: Eq, pos })
        }
        '!' =>
          if peek2_char() == Some('=') {
            advance()
            advance()
            tokens.push({ kind: Ne, pos })
          } else {
            return Err(LexError(pos, "意外的字符 '!'"))
          }
        '<' =>
          if peek2_char() == Some('=') {
            advance()
            advance()
            tokens.push({ kind: Le, pos })
          } else {
            advance()
            tokens.push({ kind: Lt, pos })
          }
        '>' =>
          if peek2_char() == Some('=') {
            advance()
            advance()
            tokens.push({ kind: Ge, pos })
          } else {
            advance()
            tokens.push({ kind: Gt, pos })
          }
        '+' => {
          advance()
          tokens.push({ kind: Plus, pos })
        }
        '-' => {
          advance()
          tokens.push({ kind: Minus, pos })
        }
        '*' => {
          advance()
          tokens.push({ kind: Star, pos })
        }
        '/' => {
          advance()
          tokens.push({ kind: Slash, pos })
        }
        '%' => {
          advance()
          tokens.push({ kind: Percent, pos })
        }
        _ => return Err(LexError(pos, "无法识别的字符: \{c}"))
      }
    }
  }
  tokens.push({ kind: Eof, pos: cur_pos() })
  Ok({ items: tokens })
}

///|
/// 记号类别的简短描述（用于错误信息）。
pub fn TokKind::describe(self : TokKind) -> String {
  match self {
    Ident(s) => "标识符 \{s}"
    IntLit(s) => "整数 \{s}"
    FloatLit(s) => "浮点数 \{s}"
    StrLit(_) => "字符串"
    LParen => "'('"
    RParen => "')'"
    Comma => "','"
    Dot => "'.'"
    Colon => "':'"
    LBrace => "'{'"
    RBrace => "'}'"
    ColonDash => "':-'"
    QuestionDash => "'?-'"
    Not => "'not'"
    Eq => "'='"
    Ne => "'!='"
    Lt => "'<'"
    Le => "'<='"
    Gt => "'>'"
    Ge => "'>='"
    Plus => "'+'"
    Minus => "'-'"
    Star => "'*'"
    Slash => "'/'"
    Percent => "'%'"
    Eof => "文件结尾"
  }
}
