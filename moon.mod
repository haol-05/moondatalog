// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "haol-05/moondatalog"

version = "0.1.1"

readme = "README.mbt.md"

repository = "https://github.com/haol-05/moondatalog"

license = "Apache-2.0"

keywords = [
  "datalog",
  "query-engine",
  "logic-programming",
  "database",
  "graph",
  "formal-verification",
]

preferred_target = "wasm"

description = "A pure MoonBit Datalog query engine with stratified negation, aggregation, static checks and moon prove formal verification."

import {
  "moonbitlang/x@0.4.49",
}
