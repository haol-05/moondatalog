// MoonDatalog —— 元组（Tuple）与关系（Relation）
//
// 关系是一组同构元组的集合，配合按首参数建立的哈希索引，
// 用于支撑 bottom-up / semi-naive 求值中的连接（join）操作。

///|
/// 一个关系元组：有序的值数组。
///
/// 自定义 `Eq` / `Hash` / `Compare`，使元组可作为哈希集合的元素，
/// 并按字典序可比，从而支持去重与排序输出。
pub struct Tuple {
  elems : Array[Value]
}

///|
pub fn make_tuple(values : Array[Value]) -> Tuple {
  { elems: values }
}

///|
pub fn Tuple::get(self : Tuple, i : Int) -> Value {
  self.elems[i]
}

///|
pub fn Tuple::length(self : Tuple) -> Int {
  self.elems.length()
}

///|
/// 以 `(a, b, c)` 形式输出。
pub fn Tuple::to_string(self : Tuple) -> String {
  let b = StringBuilder::new()
  b.write_char('(')
  let mut first = true
  for e in self.elems {
    if first {
      first = false
    } else {
      b.write_string(", ")
    }
    b.write_string(e.to_string())
  }
  b.write_char(')')
  b.to_string()
}

///|
pub impl Eq for Tuple with fn equal(self : Tuple, that : Tuple) -> Bool {
  if self.elems.length() != that.elems.length() {
    return false
  }
  let mut i = 0
  while i < self.elems.length() {
    if self.elems[i] != that.elems[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 字典序比较；长度不同时较短者在前（与常见元组序一致）。
pub impl Compare for Tuple with fn compare(self : Tuple, that : Tuple) -> Int {
  let n = self.elems.length().min(that.elems.length())
  let mut i = 0
  while i < n {
    let c = compare_values(self.elems[i], that.elems[i])
    if c != 0 {
      return c
    }
    i = i + 1
  }
  self.elems.length() - that.elems.length()
}

///|
pub impl Hash for Tuple with fn hash_combine(self : Tuple, hasher : Hasher) -> Unit {
  hasher.combine_int(self.elems.length())
  for e in self.elems {
    hasher.combine(e)
  }
}

///|
/// 一个关系（谓词实例）：同元数元组的集合，并维护按首参数的值索引。
pub struct Relation {
  arity : Int
  tuples : @hashset.HashSet[Tuple]
  idx0 : @hashmap.HashMap[Value, @hashset.HashSet[Tuple]]
}

///|
pub fn new_relation(arity : Int) -> Relation {
  { arity, tuples: @hashset.HashSet([]), idx0: @hashmap.HashMap([]) }
}

///|
pub fn Relation::arity(self : Relation) -> Int {
  self.arity
}

///|
pub fn Relation::length(self : Relation) -> Int {
  self.tuples.length()
}

///|
/// 插入一个元组；若已存在返回 `false`。
pub fn Relation::insert(self : Relation, t : Tuple) -> Bool {
  if self.tuples.contains(t) {
    return false
  }
  self.tuples.add(t)
  if t.length() > 0 {
    let key = t.get(0)
    match self.idx0.get(key) {
      Some(set) => set.add(t)
      None => {
        let set = @hashset.HashSet([])
        set.add(t)
        self.idx0.set(key, set)
      }
    }
  }
  true
}

///|
/// 批量插入并返回新增数量。
pub fn Relation::insert_all(self : Relation, ts : Iter[Tuple]) -> Int {
  let mut added = 0
  for t in ts {
    if self.insert(t) {
      added = added + 1
    }
  }
  added
}

///|
/// 遍历全部元组。
pub fn Relation::iter(self : Relation) -> Iter[Tuple] {
  self.tuples.iter()
}

///|
/// 按首参数精确查找（利用首参数索引）。
pub fn Relation::lookup0(self : Relation, v : Value) -> Iter[Tuple] {
  match self.idx0.get(v) {
    Some(set) => set.iter()
    None => Iter::empty()
  }
}

///|
/// 元组是否已存在。
pub fn Relation::contains(self : Relation, t : Tuple) -> Bool {
  self.tuples.contains(t)
}

///|
/// 移除全部元组（用于分层求值前的重置）。
pub fn Relation::clear(self : Relation) -> Unit {
  self.tuples.clear()
  self.idx0.clear()
}

///|
/// 以确定顺序输出所有元组（字典序）。
pub fn Relation::to_string(self : Relation) -> String {
  let arr : Array[Tuple] = []
  for t in self.tuples {
    arr.push(t)
  }
  arr.sort()
  let b = StringBuilder::new()
  b.write_char('{')
  let mut first = true
  for t in arr {
    if first {
      first = false
    } else {
      b.write_string(", ")
    }
    b.write_string(t.to_string())
  }
  b.write_char('}')
  b.to_string()
}
