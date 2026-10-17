"""给少数 op 补齐参数默认值（数据驱动，而不是在运行时/编译器里打补丁）。

- event.hat 的 params 默认空字典：不是所有帽子都带参数（绿旗就没有）
- control.* 的 body 默认空数组：空分支是合法的
- meta.call_method / emit_signal 的 args 默认空数组
"""
import json
import os

P = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "runtime", "ee", "defs", "ops.core.json")

WANT = {
    "event.hat": {"params": {}},
    "control.repeat": {"body": []},
    "control.forever": {"body": []},
    "control.while": {"body": []},
    "control.if": {"body": []},
    "control.if_else": {"then": [], "else": []},
    "control.warp": {"body": []},
    "meta.call_method": {"args": []},
    "meta.emit_signal": {"args": []},
}

with open(P, encoding="utf-8") as f:
    d = json.load(f)

n = 0
for o in d["ops"]:
    if o["id"] in WANT:
        o.setdefault("defaults", {}).update(WANT[o["id"]])
        n += 1

lines = ["{"]
for k in d:
    if k == "ops":
        continue
    lines.append("  " + json.dumps(k, ensure_ascii=False) + ": " + json.dumps(d[k], ensure_ascii=False) + ",")
lines.append('  "ops": [')
ops = d["ops"]
for i, o in enumerate(ops):
    lines.append("    " + json.dumps(o, ensure_ascii=False) + ("," if i < len(ops) - 1 else ""))
lines.append("  ]")
lines.append("}")

with open(P, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print(f"为 {n} 个 op 补齐默认值")
