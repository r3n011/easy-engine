"""导出 .po 中指定 msgid 附近的原始文本，用于核对解析正确性。"""
import sys

path = sys.argv[1]
targets = sys.argv[2:]
lines = open(path, encoding="utf-8").read().split("\n")

for i, l in enumerate(lines):
    if l.startswith("msgid ") and any(t in l for t in targets):
        print("=" * 60)
        lo = max(0, i - 6)
        for j in range(lo, min(len(lines), i + 4)):
            print(f"{j + 1:6}  {lines[j]}")
        print()
