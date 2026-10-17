"""删除 ops.core.json 里的孤儿 op（声明了但没有积木使用、也没有实现）。

孤儿从哪来：积木用的是带 mode 的合并 op（looks.set_size 带 mode=set|change），
所以独立的 next_costume / change_size / change_effect 永远收不到调用。

顺带保留"一行一条 op"的可读格式。
"""
import json
import os

P = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "runtime", "ee", "defs", "ops.core.json")

DROP = {"looks.next_costume", "looks.change_size", "looks.change_effect"}

with open(P, encoding="utf-8") as f:
    d = json.load(f)

before = len(d["ops"])
d["ops"] = [o for o in d["ops"] if o["id"] not in DROP]
print(f"删除 {before - len(d['ops'])} 个孤儿 op: {sorted(DROP)}")

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
print(f"剩余 {len(ops)} 个 op")
