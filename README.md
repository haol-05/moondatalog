# MoonDatalog

一个用纯 [MoonBit](https://www.moonbitlang.com/) 实现的 **Datalog 查询引擎**。

Datalog 是一种声明式逻辑查询语言，广泛应用于图分析、静态分析、数据血缘追踪与配置校验等场景。本项目实现了一个边界清晰、可嵌入的 Datalog 引擎子集，包含：

- **事实 / 规则 / 查询**：经典的 `p(...).`、`h(...) :- b1, b2.`、`?- ...` 语法
- **递归**：传递闭包等递归规则，采用 bottom-up **半朴素（semi-naive）** 求值
- **算术与比较**：`+ - * / %`、`= != < <= > >=`，支持整数与浮点
- **分层否定（stratified negation）**：`not p(...)`，通过 SCC 分层保证语义良定义
- **聚合**：Soufflé 风格的 `count / sum / min / max / avg`
- **类型安全与错误检查**：未定义谓词、元数不一致、不安全规则、不可分层否定等均在求值前报错

## 为什么做这个项目

MoonBit 生态已拥有丰富的解析器、网络库、图形库，但在「数据处理与数据库」方向仍缺少一个逻辑查询引擎（Datalog）。本项目填补这一空白，可作为图查询、静态分析、规则引擎等上层应用的内核，也可作为学习 Datalog 语义与实现的教学范例。

## 快速开始

安装 MoonBit 工具链后，在项目根目录运行测试：

```bash
moon test
```

运行示例程序（需支持 native 目标的环境，例如 Linux / 带 MSVC 的 Windows）：

```bash
moon run cmd/main -- examples/ancestor.dl
moon run cmd/main -- examples/graph_reachability.dl
moon run cmd/main -- examples/aggregation.dl
```

所有示例同样通过 `moon test` 锁定行为，任意平台都能验证。

## 作为库使用

在 `moon.pkg` 中引入：

```moonbit
import {
  "haol-05/moondatalog",
}
```

解析并求值一个程序：

```moonbit
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
| `EvalResult.answers` | 每个查询的答案元组（与 `queries` 顺序对应） |
| `relation_names(EvalResult)` | 全部谓词名（排序） |
| `render_query / render_rule / render_atom` | 将 AST 渲染为可读文本 |

## 语言语法

```
% 注释（也支持 // 行注释与 /* 块注释 */）

% 事实：谓词(常量...).
parent(alice, bob).
edge(1, 2).

% 规则：头 :- 体.
ancestor(X, Y) :- parent(X, Y).
ancestor(X, Z) :- ancestor(X, Y), parent(Y, Z).

% 否定与比较
safe(X) :- node(X), not danger(X), X != secret.

% 算术
discount(X, D) :- price(X, P), D = P * 9 / 10.

% 聚合（Soufflé 风格：结果变量 = 函数 : { 聚合变量 }）
dept_size(D, N) :- employee(X, D), N = count : { X }.

% 查询
?- ancestor(X, carol).
```

约定：

- **变量**以大写字母开头（`X`、`Y`），`_` 为匿名变量
- **符号常量**以大写字母开头之外的小写标识符表示（`alice`、`eng`）
- **字符串**用双引号（`"hello"`）、**整数**（`42`）、**浮点数**（`3.14`）
- 匿名变量 `_` 不作为聚合分组键（`score(_, S), N = max : { S }` 求全局最大值）

## 目录结构

```
.
├── moon.mod          # 模块元数据
├── *.mbt             # 库源码（词法、语法、求值引擎、分层等）
├── *_test.mbt        # 黑盒测试（47 个用例）
├── cmd/main/         # 命令行工具
├── examples/         # 示例 Datalog 程序
└── .github/          # CI 配置
```

## 许可证

[Apache-2.0](./LICENSE)
