"""查询 .po 里已有译文，用于保持术语一致。

用法: python tools/po-lookup.py <po文件> <关键词正则> [关键词正则...]
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module

_po = import_module("po-stats")


def main(po_path, patterns):
    entries, _h = _po.parse_po(po_path)
    for pat in patterns:
        rx = re.compile(pat, re.IGNORECASE)
        print(f"\n--- {pat} ---")
        n = 0
        for e in entries:
            if rx.search(e.id):
                val = e.plain if e.plain is not None else e.strs.get(0, "")
                if val and val != e.id:
                    ctx = f"  [{e.ctx}]" if e.ctx else ""
                    print(f"  {e.id!r}  =>  {val!r}{ctx}")
                    n += 1
                    if n >= 8:
                        break
        if n == 0:
            print("  (无)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
