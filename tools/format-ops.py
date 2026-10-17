"""把 ops.*.json 格式化为"一行一个 op"，方便人工扫读与 diff。

用法: python tools/format-ops.py <ops文件> [...]
"""
import json
import sys


def fmt(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    lines = ["{"]
    head_keys = [k for k in data if k != "ops"]
    for i, k in enumerate(head_keys):
        lines.append(f"  {json.dumps(k, ensure_ascii=False)}: "
                     f"{json.dumps(data[k], ensure_ascii=False)},")
    lines.append('  "ops": [')
    ops = data["ops"]
    for i, op in enumerate(ops):
        tail = "," if i < len(ops) - 1 else ""
        lines.append("    " + json.dumps(op, ensure_ascii=False) + tail)
    lines.append("  ]")
    lines.append("}")

    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{path}: {len(ops)} 个 op")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        fmt(p)
