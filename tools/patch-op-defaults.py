"""给 ops 定义里声明了 scope 参数的 op 补上默认值（整体重写，格式统一）。

数据驱动的原则：默认值写在 op 定义里，而不是硬编码在编译器里。
这样第三方扩展也能给自己的 op 声明默认值。
"""
import json
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "runtime/ee/defs/ops.core.json"

with open(path, encoding="utf-8") as f:
    data = json.load(f)

n = 0
for op in data["ops"]:
    if "scope" in op.get("args", []) and "defaults" not in op:
        op["defaults"] = {"scope": "auto"}
        n += 1

with open(path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")

# 复核
d2 = json.load(open(path, encoding="utf-8"))
with_scope = [o["id"] for o in d2["ops"] if "scope" in o.get("args", [])]
without = [o["id"] for o in d2["ops"] if "scope" in o.get("args", []) and "defaults" not in o]
print(f"补了 {n} 个；声明 scope 的 op 共 {len(with_scope)} 个；仍缺默认值的: {without}")
