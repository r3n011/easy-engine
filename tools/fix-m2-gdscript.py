"""修一批 GDScript 解析问题（撞名、循环常量、动态类型推断）。"""
import io
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "runtime", "ee")


def edit(path, pairs):
    full = os.path.join(ROOT, path)
    with open(full, encoding="utf-8") as f:
        t = f.read()
    n = 0
    for old, new in pairs:
        if old in t:
            t = t.replace(old, new)
            n += 1
        else:
            print(f"  !! 没找到: {path}: {old[:60]!r}")
    with open(full, "w", encoding="utf-8", newline="\n") as f:
        f.write(t)
    print(f"  {path}: 替换 {n} 处")


# 1) values.gd：删掉与内建常量循环引用的 const
edit("values.gd", [
    ("const INF := INF\nconst NAN := NAN\n\n", ""),
])

# 2) runtime.gd：Thread 撞原生类名 → ThreadClass；动态拼接要显式类型
edit("runtime.gd", [
    ('const Thread = preload("res://ee/thread.gd")', 'const ThreadClass = preload("res://ee/thread.gd")'),
    ("Thread.create(", "ThreadClass.create("),
    ("Thread.Status.", "ThreadClass.Status."),
    ('var method := "op_" + oid.replace(".", "_")', 'var method: String = "op_" + oid.replace(".", "_")'),
])

# 3) node_bridge.gd：emit_signal 撞 Object 的方法；clone_visual 参数名写错
edit("bridge/node_bridge.gd", [
    ("func emit_signal(target, signal_name: String, args: Array) -> void:\n\t_log(\"emit_signal\", target, [signal_name, args])",
     "func emit_signal_to(target, signal_name: String, args: Array) -> void:\n\t_log(\"emit_signal_to\", target, [signal_name, args])"),
    ("func clone_visual(target):\n\t_log(\"clone_visual\", target, [])\n\tvar c = target.duplicate_target()\n\treturn c",
     "func clone_visual(target):\n\t_log(\"clone_visual\", target, [])\n\treturn target.duplicate_target()"),
])

# 4) core_ops.gd：跟随改名
edit("providers/core_ops.gd", [
    ("bridge.emit_signal(", "bridge.emit_signal_to("),
])

# 5) expr.gd：显式类型，避免"从 Variant 推断"
edit("expr.gd", [
    ("\t\t\tvar la := Values.to_bool(_eval(a_node, lookup))", "\t\t\tvar la: bool = Values.to_bool(_eval(a_node, lookup))"),
    ("\t\t\tvar ra := Values.to_bool(_eval(a_node, lookup))", "\t\t\tvar ra: bool = Values.to_bool(_eval(a_node, lookup))"),
    ("\tfunc _primary() -> Variant:\n\t\tvar t := _peek()", "\tfunc _primary() -> Variant:\n\t\tvar t: Dictionary = _peek()"),
    ("\tfunc _peek() -> Dictionary:\n\t\treturn toks[i]", "\tfunc _peek() -> Dictionary:\n\t\treturn toks[i]"),
])

print("完成")
