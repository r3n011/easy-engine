"""扫描 Godot 编辑器源码中"疑似硬编码、未包 TTR() 的界面文案"。

这些文案不会出现在 .po 里，因此无论怎么翻译 .po 都汉化不到它们。

用法: python tools/scan-hardcoded.py [editor目录]
"""
import collections
import os
import re
import sys

PATTERNS = [
    ("set_text", re.compile(r'set_text\s*\(\s*"([^"\\]{2,})"')),
    ("set_tooltip_text", re.compile(r'set_tooltip_text\s*\(\s*"([^"\\]{2,})"')),
    ("set_title", re.compile(r'set_title\s*\([^,)]*,\s*"([^"\\]{2,})"')),
    ("add_item", re.compile(r'add_item\s*\(\s*"([^"\\]{2,})"')),
    ("set_tab_title", re.compile(r'set_tab_title\s*\([^,)]*,\s*"([^"\\]{2,})"')),
    ("set_placeholder", re.compile(r'set_placeholder\s*\(\s*"([^"\\]{2,})"')),
    ("set_text_direct", re.compile(r'Button\s*\(')),  # 占位，不计
]

SKIP_WORDS = re.compile(r"^[\s\d\.\,\:\;\-\+\*/%\(\)\[\]{}<>=_\\|~!?#@$^&\"']*$")


def main(root):
    hits = collections.Counter()
    byfile = collections.Counter()
    samples = collections.defaultdict(list)

    for dirpath, _dirs, files in os.walk(root):
        for fn in files:
            if not fn.endswith((".cpp", ".h")):
                continue
            p = os.path.join(dirpath, fn)
            try:
                txt = open(p, encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            for name, rx in PATTERNS:
                if name == "set_text_direct":
                    continue
                for m in rx.finditer(txt):
                    val = m.group(1)
                    if not re.search(r"[A-Za-z]", val):
                        continue
                    hits[name] += 1
                    rel = os.path.relpath(p, root)
                    byfile[rel] += 1
                    if len(samples[name]) < 8:
                        samples[name].append(f"{rel}: {val}")

    print("=== 疑似硬编码界面文案（未包 TTR）===")
    total = sum(hits.values())
    for k, v in hits.most_common():
        print(f"  {k:20} {v}")
    print(f"  {'合计':20} {total}")
    print()
    print("=== 命中最多的文件 ===")
    for f, c in byfile.most_common(15):
        print(f"  {c:4}  {f}")
    print()
    print("=== 样例 ===")
    for k in samples:
        print(f"-- {k}")
        for s in samples[k]:
            print("   ", s[:140])


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "engine/godot/editor")
