# MoonDatalog

一个用纯 [MoonBit](https://www.moonbitlang.com/) 实现的 **Datalog 查询引擎**，带 **形式化验证** 与完整工程化交付。

Datalog 是一种声明式逻辑查询语言，广泛应用于图分析、静态分析、数据血缘追踪与配置校验等场景。本项目实现了一个边界清晰、可嵌入、**经过机器校验** 的 Datalog 引擎，包含：

- **事实 / 规则 / 查询**：`p(...).`、`h(...) :- b1, b2.`、`?- ...`
- **递归**：bottom-up **半朴素（semi-naive）** 求值
- **算术与比较**：`+ - * / %`、`= != < <= > >=`（整数与浮点）
- **分层否定**：`not p(...)`，Tarjan SCC 自动分层
- **聚合**：Soufflé 风格 `count / sum / min / max / avg`
- **静态检查**：未定义谓词、元数不一致、不安全规则等在求值前报错
- **形式化验证**：核心纯函数经 `moon prove` 机器校验
- **工程化交付**：发布到 mooncakes.io，含 CI、50+ 测试、CLI 与示例

## 快速开始

```bash
moon test           # 运行 50 个测试
moon prove verified # 形式化验证（需 Z3 等 SMT 求解器）
```

运行示例：

```bash
moon run cmd/main -- examples/ancestor.dl
moon run cmd/main -- examples/graph_reachability.dl
moon run cmd/main -- examples/aggregation.dl
```

> Windows 提示：`moon prove` 前请将 `TMP`/`TEMP` 指向不含非 ASCII 字符的目录（如 `C:\Temp`）。

## 作为库使用

```moonbit
import {
  "haol-05/moondatalog",
}

let src = "edge(a, b). edge(b, c).\npath(X, Y) :- edge(X, Y).\npath(X, Z) :- path(X, Y), edge(Y, Z).\n?- path(a, X).\n"

match @moondatalog.parse(src) {
  Err(e) => println(e.to_string())
  Ok(program) => match @moondatalog.evaluate(program) {
    Err(e) => println(e.to_string())
    Ok(result) => {
      for t in result.answers[0] {
        println(t.to_string()) // (b)\n(c)
      }
    }
  }
}
```

## 语言语法

```
parent(alice, bob).
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Z) :- ancestor(X, Y), parent(Y, Z).
safe(X) :- node(X), not danger(X), X != secret.
dept_size(D, N) :- employee(X, D), N = count : { X }.
?- ancestor(X, carol).
```

变量以大写字母开头，`_` 为匿名变量；小写标识符为符号常量；字符串用双引号；匿名变量不作为聚合分组键。

## 形式化验证

`verified/` 子包通过 `moon prove` 对核心纯函数机器校验：

| 函数 | 契约 |
| --- | --- |
| `clamp(x, lo, hi)` | 返回值在 `[lo, hi]` 内 |
| `bounded_sum(xs, lo, hi)` | 总和在 `[lo*len, hi*len]` 内 |
| `index_of_max(xs)` | 返回全局最大值的下标 |

## 许可证

[Apache-2.0](./LICENSE)
