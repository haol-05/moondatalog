// MoonDatalog —— 求值引擎（Engine）
//
// 采用 bottom-up 求值：
//   - 语义检查：元数一致性、谓词已定义、规则安全性（range restriction）、
//     聚合用法合法性；
//   - 分层：见 stratify.mbt；
//   - 每层内用 semi-naive（半朴素）迭代求不动点；
//   - 最后对每个查询求值并投影输出。
//
// 连接（join）通过变量绑定环境（变量名 -> 值）在规则体原子间
// 逐步传播实现；否定原子在分层保证下检查补集；比较 / 赋值约束
// 在变量就绪后求值；聚合按 Soufflé 语义分组计算。

///|
/// 绑定环境：变量名 -> 值。
type Env = @hashmap.HashMap[String, Value]

///|
/// 求值结果：最终关系集合与各查询答案。
pub struct EvalResult {
  /// 全部关系（事实 + 推导结果），按谓词名索引
  relations : @hashmap.HashMap[String, Relation]
  /// 每个查询的答案元组（与 Program.queries 顺序对应）
  answers : Array[Array[Tuple]]
}

///|
/// 语义分析结果。
priv struct Analysis {
  /// 谓词 -> 元数
  arities : @hashmap.HashMap[String, Int]
  /// 按求值顺序排列的分层规则
  strata : Array[Array[Rule]]
}

///|
/// 运行完整求值：语义检查 -> 初始化 -> 分层求值 -> 回答查询。
pub fn evaluate(program : Program) -> Result[EvalResult, DlError] {
  let analysis = match analyze(program) {
    Err(e) => return Err(e)
    Ok(a) => a
  }
  let relations = match init_relations(program, analysis.arities) {
    Err(e) => return Err(e)
    Ok(r) => r
  }
  for stratum in analysis.strata {
    match eval_stratum(stratum, relations) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  match answer_queries(program, relations) {
    Err(e) => return Err(e)
    Ok(answers) => Ok({ relations, answers })
  }
}

///|
/// 语义分析：元数、已定义性、安全性、聚合用法与分层。
fn analyze(program : Program) -> Result[Analysis, DlError] {
  let arities : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  // 收集所有原子（规则头、规则体、查询体）的元数
  for rule in program.rules {
    match register_atom_arity(arities, rule.head) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    for item in rule.body {
      match item {
        Pos(a) | Neg(a) =>
          match register_atom_arity(arities, a) {
            Err(e) => return Err(e)
            Ok(_) => ()
          }
        _ => ()
      }
    }
  }
  for q in program.queries {
    for item in q.body {
      match item {
        Pos(a) | Neg(a) =>
          match register_atom_arity(arities, a) {
            Err(e) => return Err(e)
            Ok(_) => ()
          }
        _ => ()
      }
    }
  }
  // 已定义谓词（出现在规则头或事实中）
  let defined : @hashset.HashSet[String] = @hashset.HashSet([])
  for rule in program.rules {
    defined.add(rule.head.pred)
  }
  // 主体原子必须已定义
  for rule in program.rules {
    for item in rule.body {
      match item {
        Pos(a) | Neg(a) =>
          if !defined.contains(a.pred) {
            return Err(SemanticError("未定义谓词: \{a.pred}"))
          }
        _ => ()
      }
    }
  }
  for q in program.queries {
    for item in q.body {
      match item {
        Pos(a) | Neg(a) =>
          if !defined.contains(a.pred) {
            return Err(SemanticError("未定义谓词: \{a.pred}"))
          }
        _ => ()
      }
    }
  }
  // 安全性 + 聚合用法
  for rule in program.rules {
    match check_rule_safety(rule) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    match check_aggregate_use(rule) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  for q in program.queries {
    match check_query_safety(q) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  // 分层
  let strata = match stratify(program.rules) {
    Err(e) => return Err(e)
    Ok(s) => s
  }
  Ok({ arities, strata })
}

///|
fn agg_func_name(func : AggFunc) -> String {
  match func {
    AggFunc::Count => "count"
    AggFunc::Sum => "sum"
    AggFunc::Min => "min"
    AggFunc::Max => "max"
    AggFunc::Avg => "avg"
  }
}

///|
fn register_atom_arity(
  arities : @hashmap.HashMap[String, Int],
  a : Atom,
) -> Result[Unit, DlError] {
  let n = a.args.length()
  match arities.get(a.pred) {
    Some(m) =>
      if m != n {
        return Err(
          SemanticError(
            "谓词 \{a.pred} 元数不一致：已有 \{m}，本次为 \{n}（位置 \{a.pos}）",
          ),
        )
      }
    None => arities.set(a.pred, n)
  }
  Ok(())
}

///|
/// 规则安全性（range restriction）：
/// 每个变量必须由正原子或 `X = expr` 赋值绑定；聚合结果变量除外。
fn check_rule_safety(rule : Rule) -> Result[Unit, DlError] {
  // 安全变量闭包：正原子变量 + `X = expr` 赋值绑定的变量
  let safe = safe_vars(rule.body)
  // 聚合结果变量（由聚合绑定，无需正原子出现）
  let agg_vars : @hashset.HashSet[String] = @hashset.HashSet([])
  for item in rule.body {
    match item {
      Agg(agg) => {
        agg_vars.add(agg.agg_var)
        for av in agg.agg_vars {
          agg_vars.add(av)
        }
      }
      _ => ()
    }
  }
  // 否定原子中的变量必须安全
  for item in rule.body {
    match item {
      Neg(a) => {
        let vars : @hashset.HashSet[String] = @hashset.HashSet([])
        collect_atom_vars(a, vars)
        for v in vars {
          if !safe.contains(v) {
            return Err(
              SemanticError(
                "不安全规则（位置 \{rule.pos}）：否定原子中的变量 \{v} 未绑定",
              ),
            )
          }
        }
      }
      _ => ()
    }
  }
  // 比较约束中的变量必须安全
  for item in rule.body {
    match item {
      Cmp(c) => {
        let cmp_vars : @hashset.HashSet[String] = @hashset.HashSet([])
        collect_term_vars(c.lhs, cmp_vars)
        collect_term_vars(c.rhs, cmp_vars)
        for v in cmp_vars {
          if !safe.contains(v) {
            return Err(
              SemanticError(
                "不安全规则（位置 \{rule.pos}）：比较中的变量 \{v} 未绑定",
              ),
            )
          }
        }
      }
      _ => ()
    }
  }
  // 头部变量必须安全或为聚合结果变量
  let head_vars : @hashset.HashSet[String] = @hashset.HashSet([])
  collect_atom_vars(rule.head, head_vars)
  for v in head_vars {
    if !safe.contains(v) && !agg_vars.contains(v) {
      return Err(
        SemanticError(
          "不安全规则（位置 \{rule.pos}）：头部变量 \{v} 未在正原子、赋值或聚合中绑定",
        ),
      )
    }
  }
  // 聚合参数变量必须安全
  for item in rule.body {
    match item {
      Agg(agg) =>
        for av in agg.agg_vars {
          if !safe.contains(av) {
            return Err(
              SemanticError(
                "不安全规则（位置 \{rule.pos}）：聚合参数 \{av} 未绑定",
              ),
            )
          }
        }
      _ => ()
    }
  }
  Ok(())
}

///|
/// 计算规则体中的安全变量集合：正原子变量为初始集合，
/// 并迭代加入由 `X = expr`（expr 中变量已安全）绑定的变量。
fn safe_vars(body : Array[BodyItem]) -> @hashset.HashSet[String] {
  let safe : @hashset.HashSet[String] = @hashset.HashSet([])
  for item in body {
    match item {
      Pos(a) => collect_atom_vars(a, safe)
      _ => ()
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for item in body {
      match item {
        Cmp(c) =>
          if c.op == CmpOp::Eq {
            match (c.lhs, c.rhs) {
              (Var(v), rhs) =>
                if !safe.contains(v) && term_vars_safe(rhs, safe) {
                  safe.add(v)
                  changed = true
                }
              (lhs, Var(v)) =>
                if !safe.contains(v) && term_vars_safe(lhs, safe) {
                  safe.add(v)
                  changed = true
                }
              _ => ()
            }
          }
        _ => ()
      }
    }
  }
  safe
}

///|
fn term_vars_safe(t : Term, safe : @hashset.HashSet[String]) -> Bool {
  let vars : @hashset.HashSet[String] = @hashset.HashSet([])
  collect_term_vars(t, vars)
  for v in vars {
    if !safe.contains(v) {
      return false
    }
  }
  true
}

///|
/// 聚合规则合法性：聚合项必须位于体末；聚合结果变量必须出现在头部；
/// 聚合规则不得递归（头部谓词不得再次出现在本规则正原子中）。
fn check_aggregate_use(rule : Rule) -> Result[Unit, DlError] {
  let mut agg_seen = false
  for item in rule.body {
    match item {
      Agg(agg) => {
        if agg_seen {
          return Err(
            SemanticError(
              "规则中只允许一个聚合项（位置 \{agg.pos}）",
            ),
          )
        }
        agg_seen = true
        // 除 count 外，聚合参数必须恰好一个
        if agg.func != AggFunc::Count && agg.agg_vars.length() != 1 {
          return Err(
            SemanticError(
              "聚合函数 \{agg_func_name(agg.func)} 只接受一个聚合参数（位置 \{agg.pos}）",
            ),
          )
        }
        // 聚合结果变量必须出现在头部
        let head_vars : @hashset.HashSet[String] = @hashset.HashSet([])
        collect_atom_vars(rule.head, head_vars)
        if !head_vars.contains(agg.agg_var) {
          return Err(
            SemanticError(
              "聚合结果变量 \{agg.agg_var} 必须出现在规则头部（位置 \{agg.pos}）",
            ),
          )
        }
        // 头部谓词不得在本规则正原子中出现（禁止递归聚合）
        for item2 in rule.body {
          match item2 {
            Pos(a) =>
              if a.pred == rule.head.pred {
                return Err(
                  SemanticError(
                    "聚合规则不允许递归（位置 \{rule.pos}）：头部谓词 \{rule.head.pred} 出现在规则体中",
                  ),
                )
              }
            _ => ()
          }
        }
      }
      _ =>
        // 聚合项之后不允许再出现其他项
        if agg_seen {
          return Err(
            SemanticError(
              "聚合项必须位于规则体末尾（位置 \{rule.pos}）",
            ),
          )
        }
    }
  }
  Ok(())
}

///|
/// 查询安全性：查询体变量须由正原子或赋值绑定。
fn check_query_safety(q : Query) -> Result[Unit, DlError] {
  let safe = safe_vars(q.body)
  for item in q.body {
    match item {
      Neg(a) => {
        let vars : @hashset.HashSet[String] = @hashset.HashSet([])
        collect_atom_vars(a, vars)
        for v in vars {
          if !safe.contains(v) {
            return Err(
              SemanticError(
                "不安全查询（位置 \{q.pos}）：变量 \{v} 未绑定",
              ),
            )
          }
        }
      }
      Cmp(c) => {
        let vars : @hashset.HashSet[String] = @hashset.HashSet([])
        collect_term_vars(c.lhs, vars)
        collect_term_vars(c.rhs, vars)
        for v in vars {
          if !safe.contains(v) {
            return Err(
              SemanticError(
                "不安全查询（位置 \{q.pos}）：变量 \{v} 未绑定",
              ),
            )
          }
        }
      }
      _ => ()
    }
  }
  Ok(())
}

///|
fn collect_atom_vars(a : Atom, out : @hashset.HashSet[String]) -> Unit {
  for arg in a.args {
    collect_term_vars(arg, out)
  }
}

///|
fn collect_term_vars(t : Term, out : @hashset.HashSet[String]) -> Unit {
  match t {
    Const(_) => ()
    Var(name) => out.add(name)
    Neg(inner) => collect_term_vars(inner, out)
    Arith(_, l, r) => {
      collect_term_vars(l, out)
      collect_term_vars(r, out)
    }
  }
}

///|
/// 初始化关系：为所有谓词创建空关系并载入事实。
fn init_relations(
  program : Program,
  arities : @hashmap.HashMap[String, Int],
) -> Result[@hashmap.HashMap[String, Relation], DlError] {
  let relations : @hashmap.HashMap[String, Relation] = @hashmap.HashMap([])
  for pred, arity in arities {
    relations.set(pred, new_relation(arity))
  }
  for rule in program.rules {
    if rule.body.is_empty() {
      let empty_env : Env = @hashmap.HashMap([])
      let t = match eval_head(rule.head, empty_env) {
        Err(e) => return Err(e)
        Ok(tuple) => tuple
      }
      let rel = relations[rule.head.pred]
      ignore(rel.insert(t))
    }
  }
  Ok(relations)
}

///|
/// 对一层规则做 semi-naive 不动点求值。
fn eval_stratum(
  stratum : Array[Rule],
  relations : @hashmap.HashMap[String, Relation],
) -> Result[Unit, DlError] {
  // 初始 delta：本层涉及谓词的当前全部元组（事实 / 低层结果）
  let delta : @hashmap.HashMap[String, Array[Tuple]] = @hashmap.HashMap([])
  for rule in stratum {
    if !delta.contains(rule.head.pred) {
      delta.set(rule.head.pred, relation_to_array(relations[rule.head.pred]))
    }
    for item in rule.body {
      match item {
        Pos(a) | Neg(a) =>
          if !delta.contains(a.pred) {
            delta.set(a.pred, relation_to_array(relations[a.pred]))
          }
        _ => ()
      }
    }
  }
  let mut current_delta = delta
  while true {
    let new_tuples : @hashmap.HashMap[String, Array[Tuple]] = @hashmap.HashMap([])
    for rule in stratum {
      // 正原子位置表
      let pos_indices : Array[Int] = []
      for i in 0..<rule.body.length() {
        match rule.body[i] {
          Pos(_) => pos_indices.push(i)
          _ => ()
        }
      }
      if pos_indices.is_empty() {
        // 无正原子的规则（理论上是事实，已在初始化阶段处理）
        continue
      }
      for j in pos_indices {
        let p = match rule.body[j] {
          Pos(a) => Some(a.pred)
          _ => None
        }
        match p {
          None => ()
          Some(pred) =>
            match current_delta.get(pred) {
              None => () // 该谓词本层不产生新元组
              Some(d) =>
                if !d.is_empty() {
                  let envs = match
                    eval_rule_body(rule, Some(j), current_delta, relations) {
                    Err(e) => return Err(e)
                    Ok(envs) => envs
                  }
                  for env in envs {
                    let t = match eval_head(rule.head, env) {
                      Err(e) => return Err(e)
                      Ok(tuple) => tuple
                    }
                    let rel = relations[rule.head.pred]
                    if !rel.contains(t) {
                      ignore(rel.insert(t))
                      match new_tuples.get(rule.head.pred) {
                        Some(list) => list.push(t)
                        None => new_tuples.set(rule.head.pred, [t])
                      }
                    }
                  }
                }
            }
        }
      }
    }
    if new_tuples.is_empty() {
      break
    }
    current_delta = new_tuples
  }
  Ok(())
}

///|
/// 将关系元组转为数组（求值连接用）。
fn relation_to_array(rel : Relation) -> Array[Tuple] {
  let arr : Array[Tuple] = []
  for t in rel.iter() {
    arr.push(t)
  }
  arr
}

///|
/// 求值规则体，返回满足全部条件的绑定环境集合。
///
/// `delta_idx` 为 `Some(j)` 时，第 j 个正原子使用 delta 关系
/// （semi-naive 的核心：每次迭代至少一个正原子来自新推导元组）。
fn eval_rule_body(
  rule : Rule,
  delta_idx : Int?,
  delta : @hashmap.HashMap[String, Array[Tuple]],
  relations : @hashmap.HashMap[String, Relation],
) -> Result[Array[Env], DlError] {
  eval_body(rule.body, delta_idx, delta, relations)
}

///|
fn eval_query_body(
  body : Array[BodyItem],
  relations : @hashmap.HashMap[String, Relation],
) -> Result[Array[Env], DlError] {
  let empty_delta : @hashmap.HashMap[String, Array[Tuple]] = @hashmap.HashMap([])
  eval_body(body, None, empty_delta, relations)
}

///|
/// 通用的规则体 / 查询体求值。
fn eval_body(
  body : Array[BodyItem],
  delta_idx : Int?,
  delta : @hashmap.HashMap[String, Array[Tuple]],
  relations : @hashmap.HashMap[String, Relation],
) -> Result[Array[Env], DlError] {
  let mut envs : Array[Env] = [@hashmap.HashMap([])]
  let pending : Array[Cmp] = []
  for i in 0..<body.length() {
    match body[i] {
      Pos(a) => {
        let source = match delta_idx {
          Some(j) if j == i =>
            match delta.get(a.pred) {
              Some(d) => d
              None => relation_to_array(relations[a.pred])
            }
          _ => relation_to_array(relations[a.pred])
        }
        envs = join_atom(envs, a, source)
      }
      Neg(a) => envs = filter_neg(envs, a, relations)
      Cmp(c) =>
        match apply_cmp_to_envs(envs, c) {
          Ok(Some(new_envs)) => envs = new_envs
          Ok(None) => pending.push(c)
          Err(e) => return Err(e)
        }
      Agg(agg) =>
        match apply_aggregate(envs, agg) {
          Err(e) => return Err(e)
          Ok(new_envs) => envs = new_envs
        }
    }
  }
  // 处理延迟的比较（变量在后续正原子中才被绑定）
  for c in pending {
    match apply_cmp_to_envs(envs, c) {
      Ok(Some(new_envs)) => envs = new_envs
      Ok(None) =>
        return Err(
          EvalError(
            "比较约束无法求值（变量未绑定，位置 \{c.pos}），请检查规则安全性",
          ),
        )
      Err(e) => return Err(e)
    }
  }
  Ok(envs)
}

///|
/// 连接：将原子与源元组集合连接，扩展绑定环境。
fn join_atom(
  envs : Array[Env],
  atom : Atom,
  source : Array[Tuple],
) -> Array[Env] {
  let out : Array[Env] = []
  for env in envs {
    for t in source {
      match unify_atom(atom, t, env) {
        Some(ne) => out.push(ne)
        None => ()
      }
    }
  }
  out
}

///|
/// 原子与元组合一：常量匹配、变量绑定；返回 None 表示不匹配。
fn unify_atom(atom : Atom, t : Tuple, env : Env) -> Env? {
  if atom.args.length() != t.length() {
    return None
  }
  let ne = env.copy()
  for k in 0..<atom.args.length() {
    match atom.args[k] {
      Const(v) => if t.get(k) != v { return None }
      Var(name) =>
        match ne.get(name) {
          Some(v) => if v != t.get(k) { return None }
          None => ne.set(name, t.get(k))
        }
      _ => return None // 原子参数不允许算术表达式
    }
  }
  Some(ne)
}

///|
/// 否定原子：保留那些在关系中没有匹配元组的环境。
fn filter_neg(
  envs : Array[Env],
  atom : Atom,
  relations : @hashmap.HashMap[String, Relation],
) -> Array[Env] {
  let out : Array[Env] = []
  let rel = relations[atom.pred]
  for env in envs {
    let mut matched = false
    for t in rel.iter() {
      if unify_atom(atom, t, env) is Some(_) {
        matched = true
        break
      }
    }
    if !matched {
      out.push(env)
    }
  }
  out
}

///|
/// 对当前环境集合应用比较 / 赋值约束。
///
/// 返回 `Ok(Some(envs))` 表示已求值；`Ok(None)` 表示变量未就绪需延迟；
/// `Err` 表示求值错误（如类型不匹配）。
fn apply_cmp_to_envs(
  envs : Array[Env],
  cmp : Cmp,
) -> Result[Array[Env]?, DlError] {
  let out : Array[Env] = []
  let mut deferred = false
  for env in envs {
    let l = match try_eval_term(cmp.lhs, env) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let r = match try_eval_term(cmp.rhs, env) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    match (l, r) {
      (Some(a), Some(b)) =>
        match cmp_values(cmp.op, a, b) {
          Ok(true) => out.push(env)
          Ok(false) => ()
          Err(e) => return Err(e)
        }
      _ =>
        // 赋值形式：X = expr（一侧为未绑定变量，另一侧可求值）
        if cmp.op == CmpOp::Eq {
          match (cmp.lhs, cmp.rhs) {
            (Var(name), _) =>
              if r is Some(_) && l is None {
                let ne = env.copy()
                ne.set(name, r.unwrap())
                out.push(ne)
              } else {
                deferred = true
              }
            (_, Var(name)) =>
              if l is Some(_) && r is None {
                let ne = env.copy()
                ne.set(name, l.unwrap())
                out.push(ne)
              } else {
                deferred = true
              }
            _ => deferred = true
          }
        } else {
          deferred = true
        }
    }
  }
  if deferred {
    Ok(None)
  } else {
    Ok(Some(out))
  }
}

///|
/// 尝试对项求值：`Ok(Some(v))` 求值成功；`Ok(None)` 含未绑定变量；`Err` 求值错误。
fn try_eval_term(term : Term, env : Env) -> Result[Value?, DlError] {
  match term {
    Const(v) => Ok(Some(v))
    Var(name) => Ok(env.get(name))
    Neg(inner) =>
      match try_eval_term(inner, env) {
        Err(e) => return Err(e)
        Ok(v) =>
          match v {
            Some(Int(i)) => Ok(Some(Int(-i)))
            Some(Float(f)) => Ok(Some(Float(-f)))
            Some(_) => Err(EvalError("一元负号只能作用于数值"))
            None => Ok(None)
          }
      }
    Arith(op, l, r) => {
      let lv = match try_eval_term(l, env) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      let rv = match try_eval_term(r, env) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      match (lv, rv) {
        (Some(a), Some(b)) =>
          match arith(op, a, b) {
            Err(e) => Err(e)
            Ok(v) => Ok(Some(v))
          }
        _ => Ok(None)
      }
    }
  }
}

///|
/// 算术求值：整数与浮点混合按浮点处理；整数除零 / 取模零报错。
fn arith(op : BinOp, a : Value, b : Value) -> Result[Value, DlError] {
  match (a, b) {
    (Int(x), Int(y)) =>
      match op {
        BinOp::Add => Ok(Int(x + y))
        BinOp::Sub => Ok(Int(x - y))
        BinOp::Mul => Ok(Int(x * y))
        BinOp::Div =>
          if y == 0L {
            Err(EvalError("除零错误"))
          } else {
            Ok(Int(x / y))
          }
        BinOp::Mod =>
          if y == 0L {
            Err(EvalError("取模除零错误"))
          } else {
            Ok(Int(x % y))
          }
      }
    (Int(x), Float(y)) => float_arith(op, x.to_double(), y)
    (Float(x), Int(y)) => float_arith(op, x, y.to_double())
    (Float(x), Float(y)) => float_arith(op, x, y)
    _ => Err(EvalError("算术运算的操作数必须是数值类型"))
  }
}

///|
fn float_arith(op : BinOp, x : Double, y : Double) -> Result[Value, DlError] {
  match op {
    BinOp::Add => Ok(Float(x + y))
    BinOp::Sub => Ok(Float(x - y))
    BinOp::Mul => Ok(Float(x * y))
    BinOp::Div => Ok(Float(x / y))
    BinOp::Mod => Ok(Float(x % y))
  }
}

///|
/// 比较求值。相等性跨 Int/Float 数值统一比较；有序比较仅限同类数值
/// 或同字符串类型；跨类别比较报错。
fn cmp_values(op : CmpOp, a : Value, b : Value) -> Result[Bool, DlError] {
  match op {
    CmpOp::Eq => Ok(value_eq(a, b))
    CmpOp::Ne => Ok(!value_eq(a, b))
    CmpOp::Lt | CmpOp::Le | CmpOp::Gt | CmpOp::Ge => {
      let c = match ordered_compare(a, b) {
        Err(e) => return Err(e)
        Ok(c) => c
      }
      Ok(
        match op {
          CmpOp::Lt => c < 0
          CmpOp::Le => c <= 0
          CmpOp::Gt => c > 0
          _ => c >= 0
        },
      )
    }
  }
}

///|
fn value_eq(a : Value, b : Value) -> Bool {
  match (a, b) {
    (Int(x), Int(y)) => x == y
    (Float(x), Float(y)) => x == y
    (Int(x), Float(y)) => x.to_double() == y
    (Float(x), Int(y)) => x == y.to_double()
    (Sym(x), Sym(y)) => x == y
    (Str(x), Str(y)) => x == y
    _ => false
  }
}

///|
fn ordered_compare(a : Value, b : Value) -> Result[Int, DlError] {
  match (a, b) {
    (Int(x), Int(y)) => Ok(x.compare(y))
    (Float(x), Float(y)) => Ok(x.compare(y))
    (Int(x), Float(y)) => Ok(x.to_double().compare(y))
    (Float(x), Int(y)) => Ok(x.compare(y.to_double()))
    (Sym(x), Sym(y)) => Ok(x.lexical_compare(y))
    (Str(x), Str(y)) => Ok(x.lexical_compare(y))
    _ => Err(EvalError("无法比较不同类型的值: \{a} 与 \{b}"))
  }
}

///|
/// 聚合：按组键分组后计算聚合函数并绑定结果变量。
///
/// 分组键 = 当前环境中除聚合参数之外的全部变量；组内对聚合参数的
/// 取值集合（去重）计算 `count` / `sum` / `min` / `max` / `avg`。
fn apply_aggregate(
  envs : Array[Env],
  agg : Aggregate,
) -> Result[Array[Env], DlError] {
  if envs.is_empty() {
    return Ok([])
  }
  // 收集组键变量（确定性顺序）。
  // 匿名变量（`_` 生成，前缀 "__anon"）不属于分组键：
  // 它们只用于限定聚合取值集合，不参与分组。
  let group_vars : Array[String] = []
  let seen : @hashset.HashSet[String] = @hashset.HashSet([])
  for env in envs {
    for name in env.keys() {
      if !name.has_prefix("__anon") &&
        !agg.agg_vars.contains(name) &&
        !seen.contains(name) {
        seen.add(name)
        group_vars.push(name)
      }
    }
  }
  group_vars.sort()
  // 分组：组键 -> 代表环境
  let groups : @hashmap.HashMap[Tuple, Env] = @hashmap.HashMap([])
  for env in envs {
    let key_vals : Array[Value] = []
    for gv in group_vars {
      match env.get(gv) {
        Some(v) => key_vals.push(v)
        None => () // 组键变量均已绑定
      }
    }
    let key = make_tuple(key_vals)
    if !groups.contains(key) {
      groups.set(key, env)
    }
  }
  let out : Array[Env] = []
  for key, rep_env in groups {
    // 组内聚合参数的取值集合（去重）
    let agg_set : @hashset.HashSet[Tuple] = @hashset.HashSet([])
    for env in envs {
      if same_group(env, group_vars, key) {
        let vals : Array[Value] = []
        for av in agg.agg_vars {
          match env.get(av) {
            Some(v) => vals.push(v)
            None => ()
          }
        }
        agg_set.add(make_tuple(vals))
      }
    }
    let result = match compute_aggregate(agg.func, agg_set) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let ne = rep_env.copy()
    ne.set(agg.agg_var, result)
    out.push(ne)
  }
  Ok(out)
}

///|
fn same_group(env : Env, group_vars : Array[String], key : Tuple) -> Bool {
  for k in 0..<group_vars.length() {
    match env.get(group_vars[k]) {
      Some(v) => if v != key.get(k) { return false }
      None => return false
    }
  }
  true
}

///|
fn compute_aggregate(
  func : AggFunc,
  agg_set : @hashset.HashSet[Tuple],
) -> Result[Value, DlError] {
  if agg_set.is_empty() {
    return Err(EvalError("聚合作用于空组"))
  }
  match func {
    AggFunc::Count => Ok(Int(agg_set.length().to_int64()))
    AggFunc::Sum => {
      // 单列求和；含浮点则结果为浮点
      let mut int_sum = 0L
      let mut float_sum = 0.0
      let mut has_float = false
      for t in agg_set {
        match t.get(0) {
          Int(i) => int_sum = int_sum + i
          Float(f) => {
            float_sum = float_sum + f
            has_float = true
          }
          _ => return Err(EvalError("sum 只能作用于数值"))
        }
      }
      if has_float {
        Ok(Float(float_sum + int_sum.to_double()))
      } else {
        Ok(Int(int_sum))
      }
    }
    AggFunc::Min => {
      let mut best : Value? = None
      for t in agg_set {
        let v = t.get(0)
        match best {
          Some(b) => if compare_values(v, b) < 0 { best = Some(v) }
          None => best = Some(v)
        }
      }
      Ok(best.unwrap())
    }
    AggFunc::Max => {
      let mut best : Value? = None
      for t in agg_set {
        let v = t.get(0)
        match best {
          Some(b) => if compare_values(v, b) > 0 { best = Some(v) }
          None => best = Some(v)
        }
      }
      Ok(best.unwrap())
    }
    AggFunc::Avg => {
      let mut float_sum = 0.0
      let mut count = 0L
      for t in agg_set {
        match t.get(0) {
          Int(i) => {
            float_sum = float_sum + i.to_double()
            count = count + 1L
          }
          Float(f) => {
            float_sum = float_sum + f
            count = count + 1L
          }
          _ => return Err(EvalError("avg 只能作用于数值"))
        }
      }
      Ok(Float(float_sum / count.to_double()))
    }
  }
}

///|
/// 规则头求值：常量直取、变量查绑定，产出元组。
fn eval_head(head : Atom, env : Env) -> Result[Tuple, DlError] {
  let vals : Array[Value] = []
  for arg in head.args {
    match arg {
      Const(v) => vals.push(v)
      Var(name) =>
        match env.get(name) {
          Some(v) => vals.push(v)
          None => return Err(EvalError("规则头部变量未绑定: \{name}"))
        }
      _ => return Err(EvalError("规则头部不允许算术表达式"))
    }
  }
  Ok(make_tuple(vals))
}

///|
/// 回答全部查询：求值查询体、投影变量（按首次出现顺序）、去重排序。
fn answer_queries(
  program : Program,
  relations : @hashmap.HashMap[String, Relation],
) -> Result[Array[Array[Tuple]], DlError] {
  let answers : Array[Array[Tuple]] = []
  for q in program.queries {
    let envs = match eval_query_body(q.body, relations) {
      Err(e) => return Err(e)
      Ok(envs) => envs
    }
    // 查询变量按首次出现顺序
    let vars : Array[String] = []
    for item in q.body {
      match item {
        Pos(a) | Neg(a) =>
          for arg in a.args {
            collect_var_order(arg, vars)
          }
        Cmp(c) => {
          collect_var_order(c.lhs, vars)
          collect_var_order(c.rhs, vars)
        }
        Agg(agg) => vars.push(agg.agg_var)
      }
    }
    let ordered : Array[String] = []
    let seen : @hashset.HashSet[String] = @hashset.HashSet([])
    for v in vars {
      if !seen.contains(v) {
        seen.add(v)
        ordered.push(v)
      }
    }
    let set : @hashset.HashSet[Tuple] = @hashset.HashSet([])
    for env in envs {
      let vals : Array[Value] = []
      for v in ordered {
        match env.get(v) {
          Some(val) => vals.push(val)
          None => ()
        }
      }
      set.add(make_tuple(vals))
    }
    let arr : Array[Tuple] = []
    for t in set {
      arr.push(t)
    }
    arr.sort()
    answers.push(arr)
  }
  Ok(answers)
}

///|
fn collect_var_order(t : Term, out : Array[String]) -> Unit {
  match t {
    Var(name) => out.push(name)
    Neg(inner) => collect_var_order(inner, out)
    Arith(_, l, r) => {
      collect_var_order(l, out)
      collect_var_order(r, out)
    }
    Const(_) => ()
  }
}

///|
/// 获取所有关系的谓词名（排序后，便于 CLI 展示）。
pub fn relation_names(result : EvalResult) -> Array[String] {
  let names : Array[String] = []
  for k in result.relations.keys() {
    names.push(k)
  }
  names.sort()
  names
}
