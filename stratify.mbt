// MoonDatalog —— 分层（Stratification）
//
// 对带否定（`not`）的 Datalog 程序做分层检查与排序：
//   1. 构建谓词依赖图（否定边单独标记）；
//   2. 用 Tarjan 算法求强连通分量（SCC）；
//   3. 若某个 SCC 内含否定边，则程序不可分层（非 stratifiable）；
//   4. 否则按 SCC 的拓扑序（依赖在前）组织规则，逐层求值。
//
// 分层保证：求值某层时，其否定原子引用的关系已完全确定，
// 从而 `not` 的语义（在已推导集合上的补集）是良定义的。

///|
/// Tarjan 强连通分量算法的工作状态。
priv struct Tarjan {
  /// 邻接表：谓词 -> 其后继（规则头部依赖的主体谓词）
  adj : @hashmap.HashMap[String, Array[String]]
  /// 否定依赖边集合
  neg : @hashset.HashSet[(String, String)]
  mut idx_counter : Int
  index : @hashmap.HashMap[String, Int]
  lowlink : @hashmap.HashMap[String, Int]
  on_stack : @hashset.HashSet[String]
  stack : Array[String]
  /// 完成顺序收集的 SCC（先完成的在列表前部，即反向拓扑序）
  scc_list : Array[Array[String]]
  /// 谓词 -> SCC 编号
  scc_id : @hashmap.HashMap[String, Int]
}

///|
fn new_tarjan() -> Tarjan {
  {
    adj: @hashmap.HashMap([]),
    neg: @hashset.HashSet([]),
    idx_counter: 0,
    index: @hashmap.HashMap([]),
    lowlink: @hashmap.HashMap([]),
    on_stack: @hashset.HashSet([]),
    stack: [],
    scc_list: [],
    scc_id: @hashmap.HashMap([]),
  }
}

///|
fn add_edge(t : Tarjan, from : String, to : String) -> Unit {
  match t.adj.get(from) {
    Some(list) => list.push(to)
    None => t.adj.set(from, [to])
  }
}

///|
fn Tarjan::strongconnect(self : Tarjan, v : String) -> Unit {
  self.index.set(v, self.idx_counter)
  self.lowlink.set(v, self.idx_counter)
  self.idx_counter = self.idx_counter + 1
  self.stack.push(v)
  self.on_stack.add(v)
  for w in self.adj.get_or_default(v, []) {
    if !self.index.contains(w) {
      self.strongconnect(w)
      let lv = self.lowlink[v]
      let lw = self.lowlink[w]
      self.lowlink.set(v, if lw < lv { lw } else { lv })
    } else if self.on_stack.contains(w) {
      let lv = self.lowlink[v]
      let iw = self.index[w]
      self.lowlink.set(v, if iw < lv { iw } else { lv })
    }
  }
  if self.lowlink[v] == self.index[v] {
    let scc : Array[String] = []
    while true {
      match self.stack.pop() {
        Some(w) => {
          self.on_stack.remove(w)
          scc.push(w)
          if w == v {
            break
          }
        }
        None => break
      }
    }
    let id = self.scc_list.length()
    for node in scc {
      self.scc_id.set(node, id)
    }
    self.scc_list.push(scc)
  }
}

///|
/// 对规则集做分层。
///
/// 返回按求值顺序排列的分层（每层为一组规则）；若程序不可分层
/// （否定依赖存在递归环），返回语义错误。
pub fn stratify(rules : Array[Rule]) -> Result[Array[Array[Rule]], DlError] {
  let t = new_tarjan()
  for rule in rules {
    if !t.adj.contains(rule.head.pred) {
      t.adj.set(rule.head.pred, [])
    }
    for item in rule.body {
      match item {
        Pos(a) => add_edge(t, rule.head.pred, a.pred)
        Neg(a) => {
          add_edge(t, rule.head.pred, a.pred)
          t.neg.add((rule.head.pred, a.pred))
        }
        _ => ()
      }
    }
  }
  // 节点按字典序遍历，保证结果确定性
  let nodes : Array[String] = []
  for k in t.adj.keys() {
    nodes.push(k)
  }
  nodes.sort()
  for v in nodes {
    if !t.index.contains(v) {
      t.strongconnect(v)
    }
  }
  // 检查否定边是否落在同一个 SCC 内
  for pair in t.neg {
    let (a, b) = pair
    let ida = t.scc_id[a]
    let idb = t.scc_id[b]
    if ida == idb {
      return Err(
        SemanticError(
          "程序不可分层：谓词 \{a} 通过否定依赖 \{b} 形成递归环（`not` 不能出现在递归规则中）",
        ),
      )
    }
  }
  // 求值顺序：Tarjan 的弹栈顺序即汇点优先（被依赖者先完成）。
  // 依赖关系为 head -> body（head 依赖 body），因此汇点 = 被依赖的谓词，
  // 必须先求值；直接按弹栈顺序（scc_list 原序）组织分层即可。
  let strata : Array[Array[Rule]] = []
  let n = t.scc_list.length()
  let mut sid = 0
  while sid < n {
    let rules_in_scc : Array[Rule] = []
    for rule in rules {
      if t.scc_id[rule.head.pred] == sid {
        rules_in_scc.push(rule)
      }
    }
    if !rules_in_scc.is_empty() {
      strata.push(rules_in_scc)
    }
    sid = sid + 1
  }
  Ok(strata)
}
