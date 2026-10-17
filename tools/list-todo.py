"""打印待翻译清单（TSV），供翻译与回填。

用法: python tools/list-todo.py [清单.json]
"""
import json
import sys

rows = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "docs/zh-ui-todo.json", encoding="utf-8"))
print(f"# 共 {len(rows)} 条")
for r in sorted(rows, key=lambda x: (x["kind"], x["msgid"])):
    print(f"{r['kind']}\t{r['context']}\t{r['msgid']}")
