"""继续修 GDScript 的类型推断与参数名问题。"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "runtime", "ee")


def edit(path, pairs):
    full = os.path.join(ROOT, path)
    with open(full, encoding="utf-8") as f:
        t = f.read()
    for old, new in pairs:
        if old not in t:
            print(f"  !! 没找到 {path}: {old[:70]!r}")
            continue
        t = t.replace(old, new)
    with open(full, "w", encoding="utf-8", newline="\n") as f:
        f.write(t)
    print(f"  {path} 已更新")


edit("expr.gd", [
    ("\tvar a := _eval(a_node, lookup)\n\tvar b := _eval(b_node, lookup)",
     "\tvar a: Variant = _eval(a_node, lookup)\n\tvar b: Variant = _eval(b_node, lookup)"),
    ("\t\tvar t := toks[i]\n\t\treturn t[\"k\"] == \"op\"",
     "\t\tvar t: Dictionary = toks[i]\n\t\treturn t[\"k\"] == \"op\""),
    ("\tfunc _peek() -> Dictionary:\n\t\treturn toks[i]",
     "\tfunc _peek() -> Dictionary:\n\t\treturn toks[i]"),
])

edit("bridge/node_bridge.gd", [
    ("func is_key_pressed(key: String) -> bool:\n\t_log(\"is_key_pressed\", target, [key])",
     "func is_key_pressed(key: String) -> bool:\n\t_log(\"is_key_pressed\", null, [key])"),
])

print("完成")
