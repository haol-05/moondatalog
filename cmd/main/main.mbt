// MoonDatalog —— 命令行工具
//
// 用法：
//   moon run cmd/main -- <file.dl> [--relations] [--trace]
//
// 读取一个 Datalog 源文件，求值后打印每个查询的结果；
// `--relations` 额外打印全部关系；`--trace` 打印每个谓词的
// 元组数量概览。

///|
fn usage() -> String {
  "用法: moondatalog <file.dl> [--relations] [--trace]"
}

///|
fn main {
  let args = @env.args()
  // args[0] 为程序名，用户参数从 args[1] 开始
  let mut file : String? = None
  let mut show_relations = false
  let mut trace = false
  for i in 1..<args.length() {
    let a = args[i]
    if a == "--relations" {
      show_relations = true
    } else if a == "--trace" {
      trace = true
    } else if a == "--help" || a == "-h" {
      println(usage())
      return
    } else if file is None {
      file = Some(a)
    } else {
      println(usage())
      @sys.exit(2)
    }
  }
  let path = match file {
    Some(p) => p
    None => {
      println("错误: 请提供 Datalog 源文件路径")
      println(usage())
      @sys.exit(2)
      "" // 不可达
    }
  }
  let src = @fs.read_file_to_string(path) catch {
    _ => {
      println("错误: 无法读取文件: \{path}")
      @sys.exit(1)
      "" // 不可达：exit 已终止进程
    }
  }
  match @moondatalog.parse(src) {
    Err(e) => {
      println(e.to_string())
      @sys.exit(1)
    }
    Ok(program) =>
      match @moondatalog.evaluate(program) {
        Err(e) => {
          println(e.to_string())
          @sys.exit(1)
        }
        Ok(result) => {
          for i in 0..<program.queries.length() {
            println("?- " + @moondatalog.render_query(program.queries[i]))
            let tuples = result.answers[i]
            if tuples.is_empty() {
              println("  (无解)")
            } else {
              for t in tuples {
                println("  " + t.to_string())
              }
            }
          }
          if trace {
            println("")
            println("== 关系概览 ==")
            for name in @moondatalog.relation_names(result) {
              let rel = result.relations[name]
              println("\{name}: \{rel.length()} 个元组")
            }
          }
          if show_relations {
            println("")
            println("== 全部关系 ==")
            for name in @moondatalog.relation_names(result) {
              let rel = result.relations[name]
              if rel.length() > 0 {
                println("\{name}\{rel.to_string()}")
              }
            }
          }
        }
      }
  }
}
