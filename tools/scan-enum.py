"""统计 Godot 里"枚举标签"（PROPERTY_HINT_ENUM 的 hint_string）的可翻译面。

这些标签在检查器里直接显示给用户（旋转模式、处理模式、纹理过滤……），
但目前全引擎都没有走翻译流程。

用法: python tools/scan-enum.py [engine目录]
"""
import collections
import os
import re
import sys

SKIP_DIRS = {"thirdparty", "bin", ".git", "obj", "tests"}

# PROPERTY_HINT_ENUM, "A,B,C"   或  PROPERTY_HINT_ENUM, "A,B", ...
RE_ENUM = re.compile(r'PROPERTY_HINT_ENUM(?:_WITH_ALPHA)?\s*,\s*"((?:[^"\\]|\\.)*)"')


def main(root):
    values = collections.Counter()
    byfile = collections.Counter()
    n_hints = 0
    n_files = 0

    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for fn in files:
            if not fn.endswith((".cpp", ".h")):
                continue
            p = os.path.join(dirpath, fn)
            try:
                txt = open(p, encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            if "PROPERTY_HINT_ENUM" not in txt:
                continue
            hits = RE_ENUM.findall(txt)
            if not hits:
                continue
            n_files += 1
            rel = os.path.relpath(p, root)
            for h in hits:
                n_hints += 1
                byfile[rel] += 1
                for part in h.split(","):
                    label = part.split(":")[0].strip()
                    if label and re.search(r"[A-Za-z]", label):
                        values[label] += 1

    print("=== 枚举标签（PROPERTY_HINT_ENUM）统计 ===")
    print(f"  含枚举的属性定义处: {n_hints}")
    print(f"  涉及文件: {n_files}")
    print(f"  唯一标签: {len(values)}")
    print(f"  标签出现总次数: {sum(values.values())}")
    print()
    print("  --- 出现最多的 40 个标签 ---")
    for v, c in values.most_common(40):
        print(f"    x{c:<4} {v!r}")
    print()
    print("  --- 涉及最多的文件 ---")
    for f, c in byfile.most_common(15):
        print(f"    {c:5}  {f}")
    print()
    print("  --- 全部唯一标签（按字母序）---")
    for v in sorted(values):
        print("   ", v)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "engine/godot")
