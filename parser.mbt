// MoonDatalog —— 递归下降语法分析器（Parser）
//
// 文法（简化 EBNF）：
//
//   program   := clause*
//   clause    := fact | rule | query
//   fact      := atom '.'
//   rule      := atom ':-' body '.'
//   query     := '?-' body '.'
//   body      := body_item (',' body_item)*
//   body_item := atom | 'not' atom | cmp | aggregate
//   aggregate := IDENT '=' agg_func ':' '{' IDENT (',' IDENT)* '}'
//   agg_func  := 'count' | 'sum' | 'min' | 'max' | 'avg'
//   cmp       := expr cmp_op expr
//   cmp_op    := '=' | '!=' | '<' | '<=' | '>' | '>='
//   expr      := term (('+' | '-') term)*
//   term      := ('*' | '/' | '%') 优先级高于加减
//   atom      := IDENT '(' term (',' term)* ')'
//
// 原子参数只允许常量或变量；算术表达式仅允许出现在比较约束中。

///|
/// 解析器内部状态。
priv struct Parser {
  toks : Array[Token]
  mut cursor : Int
  /// 匿名变量 `_` 的生成计数器
  mut anon : Int
}

///|
fn Parser::peek(self : Parser) -> Token {
  self.toks[self.cursor]
}

///|
fn Parser::peek2(self : Parser) -> Token {
  if self.cursor + 1 < self.toks.length() {
    self.toks[self.cursor + 1]
  } else {
    self.toks[self.toks.length() - 1]
  }
}

///|
fn Parser::advance(self : Parser) -> Token {
  let t = self.toks[self.cursor]
  if self.cursor + 1 < self.toks.length() {
    self.cursor = self.cursor + 1
  }
  t
}

///|
fn Parser::at(self : Parser, k : TokKind) -> Bool {
  self.peek().kind == k
}

///|
/// 为 `_` 匿名变量生成唯一变量名。
fn Parser::fresh_anon(self : Parser) -> String {
  let name = "__anon\{self.anon}"
  self.anon = self.anon + 1
  name
}

///|
/// 解析完整程序。
pub fn parse(src : String) -> Result[Program, DlError] {
  match lex(src) {
    Err(e) => Err(e)
    Ok(toks) => {
      let p = { toks: toks.items, cursor: 0, anon: 0 }
      let rules : Array[Rule] = []
      let queries : Array[Query] = []
      while !p.at(Eof) {
        match p.parse_clause() {
          Err(e) => return Err(e)
          Ok(clause) =>
            match clause {
              RuleItem(r) => rules.push(r)
              QueryItem(q) => queries.push(q)
            }
        }
      }
      Ok({ rules, queries })
    }
  }
}

///|
/// 一条子句：规则（含事实）或查询。
priv enum Clause {
  RuleItem(Rule)
  QueryItem(Query)
}

///|
fn Parser::parse_clause(self : Parser) -> Result[Clause, DlError] {
  if self.at(QuestionDash) {
    let qpos = self.advance().pos
    match self.parse_body() {
      Err(e) => Err(e)
      Ok(body) => {
        if !self.at(Dot) {
          return Err(self.unexpected("查询应以 '.' 结尾"))
        }
        ignore(self.advance())
        Ok(QueryItem({ body, pos: qpos }))
      }
    }
  } else {
    match self.parse_atom() {
      Err(e) => Err(e)
      Ok(head) =>
        if self.at(ColonDash) {
          ignore(self.advance())
          match self.parse_body() {
            Err(e) => Err(e)
            Ok(body) => {
              if !self.at(Dot) {
                return Err(self.unexpected("规则应以 '.' 结尾"))
              }
              ignore(self.advance())
              Ok(RuleItem({ head, body, pos: head.pos }))
            }
          }
        } else if self.at(Dot) {
          ignore(self.advance())
          // 事实：无体规则
          Ok(RuleItem({ head, body: [], pos: head.pos }))
        } else {
          Err(self.unexpected("期望 ':-'、'.' 或 '?-'"))
        }
    }
  }
}

///|
fn Parser::parse_body(self : Parser) -> Result[Array[BodyItem], DlError] {
  let items : Array[BodyItem] = []
  let mut done = false
  while !done {
    match self.parse_body_item() {
      Err(e) => return Err(e)
      Ok(item) => {
        items.push(item)
        if self.at(Comma) {
          ignore(self.advance())
        } else {
          done = true
        }
      }
    }
  }
  Ok(items)
}

///|
fn Parser::parse_body_item(self : Parser) -> Result[BodyItem, DlError] {
  if self.at(Not) {
    ignore(self.advance())
    match self.parse_atom() {
      Err(e) => Err(e)
      Ok(a) => Ok(Neg(a))
    }
  } else if self.peek().kind is Ident(_) && self.peek2().kind == Eq {
    // 可能是聚合：N = func : { ... }；先试探解析
    match self.try_parse_aggregate() {
      Some(a) => Ok(Agg(a))
      None => self.parse_cmp()
    }
  } else if self.peek().kind is Ident(_) {
    // 若后面紧跟 '(' 则为原子，否则为比较（形如 X < 5）
    match self.peek2().kind {
      LParen =>
        match self.parse_atom() {
          Err(e) => Err(e)
          Ok(a) => Ok(Pos(a))
        }
      _ => self.parse_cmp()
    }
  } else {
    self.parse_cmp()
  }
}

///|
/// 尝试解析聚合项；失败（非聚合形式）返回 `None`。
fn Parser::try_parse_aggregate(self : Parser) -> Aggregate? {
  let save = self.cursor
  match self.peek().kind {
    Ident(agg_var) => {
      if self.peek2().kind != Eq {
        return None
      }
      // 试探性推进，失败则回退
      ignore(self.advance()) // agg_var
      ignore(self.advance()) // =
      match self.peek().kind {
        Ident(func) => {
          if !is_agg_func_name(func) {
            self.cursor = save
            return None
          }
          ignore(self.advance())
          if !self.at(Colon) {
            self.cursor = save
            return None
          }
          ignore(self.advance())
          if !self.at(LBrace) {
            self.cursor = save
            return None
          }
          ignore(self.advance())
          let vars : Array[String] = []
          let mut done = false
          while !done {
            match self.peek().kind {
              Ident(v) => {
                if !is_variable_name(v) {
                  self.cursor = save
                  return None
                }
                ignore(self.advance())
                vars.push(v)
              }
              _ => {
                self.cursor = save
                return None
              }
            }
            if self.at(Comma) {
              ignore(self.advance())
            } else {
              done = true
            }
          }
          if !self.at(RBrace) {
            self.cursor = save
            return None
          }
          let pos = self.advance().pos // RBrace 位置
          Some({ agg_var, func: agg_func_of_name(func), agg_vars: vars, pos })
        }
        _ => {
          self.cursor = save
          None
        }
      }
    }
    _ => None
  }
}

///|
fn is_agg_func_name(s : String) -> Bool {
  s == "count" || s == "sum" || s == "min" || s == "max" || s == "avg"
}

///|
fn agg_func_of_name(s : String) -> AggFunc {
  match s {
    "count" => Count
    "sum" => Sum
    "min" => Min
    "max" => Max
    _ => Avg
  }
}

///|
fn Parser::parse_cmp(self : Parser) -> Result[BodyItem, DlError] {
  let lhs_pos = self.peek().pos
  match self.parse_expr() {
    Err(e) => Err(e)
    Ok(lhs) => {
      let op = match self.peek().kind {
        Eq => Some(CmpOp::Eq)
        Ne => Some(CmpOp::Ne)
        Lt => Some(CmpOp::Lt)
        Le => Some(CmpOp::Le)
        Gt => Some(CmpOp::Gt)
        Ge => Some(CmpOp::Ge)
        _ => None
      }
      match op {
        None =>
          Err(self.unexpected("期望比较运算符 (=, !=, <, <=, >, >=)"))
        Some(op_kind) => {
          ignore(self.advance())
          match self.parse_expr() {
            Err(e) => Err(e)
            Ok(rhs) => Ok(Cmp({ op: op_kind, lhs, rhs, pos: lhs_pos }))
          }
        }
      }
    }
  }
}

///|
/// 加减优先级。
fn Parser::parse_expr(self : Parser) -> Result[Term, DlError] {
  match self.parse_term_mul() {
    Err(e) => Err(e)
    Ok(lhs) => {
      let mut cur = lhs
      while true {
        let op = match self.peek().kind {
          Plus => Some(BinOp::Add)
          Minus => Some(BinOp::Sub)
          _ => None
        }
        match op {
          None => break
          Some(binop) => {
            ignore(self.advance())
            match self.parse_term_mul() {
              Err(e) => return Err(e)
              Ok(rhs) => cur = Arith(binop, cur, rhs)
            }
          }
        }
      }
      Ok(cur)
    }
  }
}

///|
/// 乘除模优先级。
fn Parser::parse_term_mul(self : Parser) -> Result[Term, DlError] {
  match self.parse_term_primary() {
    Err(e) => Err(e)
    Ok(lhs) => {
      let mut cur = lhs
      while true {
        let op = match self.peek().kind {
          Star => Some(BinOp::Mul)
          Slash => Some(BinOp::Div)
          Percent => Some(BinOp::Mod)
          _ => None
        }
        match op {
          None => break
          Some(binop) => {
            ignore(self.advance())
            match self.parse_term_primary() {
              Err(e) => return Err(e)
              Ok(rhs) => cur = Arith(binop, cur, rhs)
            }
          }
        }
      }
      Ok(cur)
    }
  }
}

///|
fn Parser::parse_term_primary(self : Parser) -> Result[Term, DlError] {
  let t = self.peek()
  match t.kind {
    IntLit(text) => {
      ignore(self.advance())
      match parse_int(text) {
        Some(v) => Ok(Const(v))
        None => Err(ParseError(t.pos, "整数超出范围: \{text}"))
      }
    }
    FloatLit(text) => {
      ignore(self.advance())
      match parse_float(text) {
        Some(v) => Ok(Const(v))
        None => Err(ParseError(t.pos, "浮点数非法: \{text}"))
      }
    }
    StrLit(text) => {
      ignore(self.advance())
      Ok(Const(Str(text)))
    }
    Ident(name) => {
      ignore(self.advance())
      if is_variable_name(name) {
        if name == "_" {
          Ok(Var(self.fresh_anon()))
        } else {
          Ok(Var(name))
        }
      } else {
        // 小写标识符：符号常量
        Ok(Const(Sym(name)))
      }
    }
    Minus => {
      ignore(self.advance())
      match self.parse_term_primary() {
        Err(e) => Err(e)
        Ok(inner) => Ok(Neg(inner))
      }
    }
    LParen => {
      ignore(self.advance())
      match self.parse_expr() {
        Err(e) => Err(e)
        Ok(inner) => {
          if !self.at(RParen) {
            return Err(self.unexpected("期望 ')'"))
          }
          ignore(self.advance())
          Ok(inner)
        }
      }
    }
    _ => Err(self.unexpected("期望项（常量、变量或表达式）"))
  }
}

///|
fn Parser::parse_atom(self : Parser) -> Result[Atom, DlError] {
  match self.peek().kind {
    Ident(pred) => {
      let pos = self.peek().pos
      if !is_variable_name(pred) {
        ignore(self.advance())
        if !self.at(LParen) {
          return Err(ParseError(pos, "谓词 \{pred} 后应有 '('"))
        }
        ignore(self.advance())
        let args : Array[Term] = []
        if !self.at(RParen) {
          let mut done = false
          while !done {
            match self.parse_atom_arg() {
              Err(e) => return Err(e)
              Ok(arg) => {
                args.push(arg)
                if self.at(Comma) {
                  ignore(self.advance())
                } else {
                  done = true
                }
              }
            }
          }
        }
        if !self.at(RParen) {
          return Err(self.unexpected("期望 ')'"))
        }
        ignore(self.advance())
        Ok({ pred, args, pos })
      } else {
        Err(ParseError(pos, "谓词名不能以大写字母开头: \{pred}"))
      }
    }
    _ => Err(self.unexpected("期望谓词原子"))
  }
}

///|
/// 原子参数：仅允许常量或变量。
fn Parser::parse_atom_arg(self : Parser) -> Result[Term, DlError] {
  let t = self.peek()
  match t.kind {
    IntLit(text) => {
      ignore(self.advance())
      match parse_int(text) {
        Some(v) => Ok(Const(v))
        None => Err(ParseError(t.pos, "整数超出范围: \{text}"))
      }
    }
    FloatLit(text) => {
      ignore(self.advance())
      match parse_float(text) {
        Some(v) => Ok(Const(v))
        None => Err(ParseError(t.pos, "浮点数非法: \{text}"))
      }
    }
    StrLit(text) => {
      ignore(self.advance())
      Ok(Const(Str(text)))
    }
    Ident(name) => {
      ignore(self.advance())
      if is_variable_name(name) {
        if name == "_" {
          Ok(Var(self.fresh_anon()))
        } else {
          Ok(Var(name))
        }
      } else {
        Ok(Const(Sym(name)))
      }
    }
    Minus => {
      // 支持负数字面量作为原子参数
      let negpos = t.pos
      ignore(self.advance())
      match self.peek().kind {
        IntLit(text) => {
          ignore(self.advance())
          match parse_int(text) {
            Some(Int(i)) => Ok(Const(Int(-i)))
            _ => Err(ParseError(negpos, "负数字面量非法"))
          }
        }
        FloatLit(text) => {
          ignore(self.advance())
          match parse_float(text) {
            Some(Float(f)) => Ok(Const(Float(-f)))
            _ => Err(ParseError(negpos, "负数字面量非法"))
          }
        }
        _ => Err(ParseError(negpos, "原子参数中 '-' 后应为数字"))
      }
    }
    _ => Err(self.unexpected("原子参数仅允许常量或变量"))
  }
}

///|
/// 生成"意外的记号"错误。
fn Parser::unexpected(self : Parser, msg : String) -> DlError {
  let t = self.peek()
  ParseError(t.pos, "\{msg}，但遇到 \{t.kind.describe()}")
}
