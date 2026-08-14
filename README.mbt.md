# MoonDatalog

一个用纯 [MoonBit](https://www.moonbitlang.com/) 实现的 **Datalog 查询引擎**。

Datalog 是一种声明式逻辑查询语言，广泛应用于图分析、静态分析、数据血缘追踪与配置校验等场景。本项目实现了一个边界清晰、可嵌入的 Datalog 引擎子集，包含：

- **事实 / 规则 / 查询**：经典的 `p(...).`、`h(...) :- b1, b2.`、`?- ...` 语法
- **递归**：传递闭包等递归规则，采用 bottom-up **半朴素（semi-naive）** 求值
- **算术与比较**：`+ - * / %`、`= != < <= > >=`，支持整数与浮点
- **分层否定（stratified negation）**：`not p(...)`，通过 SCC 分层保证语义良定义
- **聚合**：Soufflé 风格的 `count / sum / min / max / avg`
- **类型安全与错误检查**：未定义谓词、元数不一致、不安全规则、不可分层否定等均在求值前报错

## 快速开始

安装 MoonBit 工具链后，在项目根目录运行测试：

```bash
moon test
```

运行示例程序：

```bash
moon run cmd/main -- examples/ancestor.dl
moon run cmd/main -- examples/graph_reachability.dl
moon run cmd/main -- examples/aggregation.dl
```

## 作为库使用

```moonbit nocheck
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

公开 API：

| 函数 | 说明 |
| --- | --- |
| `parse(String) -> Result[Program, DlError]` | 解析 Datalog 源码为 AST |
| `evaluate(Program) -> Result[EvalResult, DlError]` | 求值并回答查询 |
| `EvalResult.relations` | 全部关系（事实 + 推导结果） |
| `EvalResult.answers` | 每个查询的答案元组 |
| `relation_names(EvalResult)` | 全部谓词名（排序） |
| `render_query / render_rule / render_atom` | 将 AST 渲染为可读文本 |

## 语言语法

```
% 注释（也支持 // 与 /* ... */）

% 事实：谓词(常量...).
parent(alice, bob).

% 规则：头 :- 体.
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Z) :- ancestor(X, Y), parent(Y, Z).

% 否定与比较
safe(X) :- node(X), not danger(X), X != secret.

% 聚合（Soufflé 风格）
dept_size(D, N) :- employee(X, D), N = count : { X }.

% 查询
?- ancestor(X, carol).
```

约定：变量以大写字母开头，`_` 为匿名变量；小写标识符为符号常量；字符串用双引号；匿名变量不作为聚合分组键。

## 许可证

[Apache-2.0](./LICENSE)
