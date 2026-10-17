"""筛出"真·界面文案"漏翻项（排除内部标识符）。

PNAME 里大量是内部键名（time/fps、UNASSIGNED_VARIABLE、blend），
上游刻意不翻译。本脚本把二者分开，只输出真正会显示给用户看的文案。

用法: python tools/zh-todo.py [engine目录]
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module

_ext = import_module("extract-ttr")
_po = import_module("po-stats")

# 判定为"内部标识符"（不需要翻译）
RE_INTERNAL = [
    re.compile(r"^[a-z0-9_/\.]+$"),      # 全小写 snake_case / 路径: time/fps, joint_constraints/bias
    re.compile(r"^[A-Z0-9_]+$"),         # 全大写: UNASSIGNED_VARIABLE
    re.compile(r"^\d+$"),
    re.compile(r"^[\W_]+$"),             # 纯符号
]


def is_internal(s):
    if s.strip() != s or not s:
        return True
    return any(r.match(s) for r in RE_INTERNAL)


def main(root):
    base = os.path.join(root, "editor", "translations")
    po_paths = [
        os.path.join(base, "editor", "zh_Hans.po"),
        os.path.join(base, "extractable", "zh_Hans.po"),
        os.path.join(base, "properties", "zh_Hans.po"),
    ]
    known, _counts = _ext.load_po(po_paths)

    found = {}   # (kind, ctx, msgid) -> {count, files}
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in _ext.SKIP_DIRS]
        for fn in files:
            if not fn.endswith((".cpp", ".h")):
                continue
            p = os.path.join(dirpath, fn)
            try:
                txt = open(p, encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            if not any(k in txt for k in _ext.FUNCS):
                continue
            rel = os.path.relpath(p, root)
            for kind, mid, plural, ctx in _ext.scan(_ext.strip_comments(txt)):
                for m in ([mid] + ([plural] if plural else [])):
                    key = (kind, ctx, m)
                    if key in known:
                        continue
                    d = found.setdefault(key, {"count": 0, "files": []})
                    d["count"] += 1
                    if rel not in d["files"]:
                        d["files"].append(rel)

    ui = []
    internal = []
    for (kind, ctx, m), d in found.items():
        rec = {"kind": kind, "context": ctx, "msgid": m,
               "count": d["count"], "files": d["files"][:2]}
        (internal if is_internal(m) else ui).append(rec)

    ui.sort(key=lambda r: (-r["count"], r["msgid"]))
    internal.sort(key=lambda r: r["msgid"])

    print(f"标记总数: {len(found)}")
    print(f"  真·界面文案: {len(ui)}")
    print(f"  内部标识符  : {len(internal)}（上游刻意不翻，忽略）")
    print()
    print("=== 真·界面文案漏翻清单 ===")
    for r in ui:
        tag = f" [上下文: {r['context']}]" if r["context"] else ""
        print(f"  x{r['count']:<3} ({r['kind']}) {r['msgid'][:105]!r}{tag}")
        print(f"        {r['files'][0]}")

    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "docs", "zh-ui-todo.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(ui, f, ensure_ascii=False, indent=2)
    print(f"\n已写出: {out}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "engine/godot")
