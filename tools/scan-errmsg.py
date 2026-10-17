"""统计 Godot 源码中"无法被翻译"的用户可见文本。

界面文案（TTR）已全部进 .po；但下面这些是直接写死的，
中文界面下一旦触发就会蹦出英文：
  - ERR_PRINT / WARN_PRINT / print_error / print_line   → 报错与警告
  - r_error = "..."                                     → 错误码描述
  - ERR_FAIL_* 宏里的消息

用法: python tools/scan-errmsg.py [engine目录]
"""
import collections
import os
import re
import sys

PATTERNS = [
    ("ERR_PRINT", re.compile(r'ERR_PRINT\s*\(\s*"([^"\\]{4,})"')),
    ("WARN_PRINT", re.compile(r'WARN_PRINT\s*\(\s*"([^"\\]{4,})"')),
    ("print_error", re.compile(r'print_error\s*\(\s*"([^"\\]{4,})"')),
    ("r_error", re.compile(r'r_error\s*=\s*"([^"\\]{4,})"')),
    ("ERR_FAIL_MSG", re.compile(r'ERR_FAIL_MSG\s*\(\s*"([^"\\]{4,})"')),
    ("ERR_FAIL_COND_MSG", re.compile(r'ERR_FAIL_COND_MSG\s*\([^,]+,\s*"([^"\\]{4,})"')),
    ("ERR_FAIL_NULL_MSG", re.compile(r'ERR_FAIL_NULL_MSG\s*\([^,]+,\s*"([^"\\]{4,})"')),
]

SKIP_DIRS = {"thirdparty", "bin", ".git", "obj"}


def main(root):
    hits = collections.Counter()
    bydir = collections.Counter()
    samples = collections.defaultdict(list)
    total = 0

    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for fn in files:
            if not fn.endswith((".cpp", ".h", ".c")):
                continue
            p = os.path.join(dirpath, fn)
            try:
                txt = open(p, encoding="utf-8", errors="ignore").read()
            except OSError:
                continue
            for name, rx in PATTERNS:
                for m in rx.finditer(txt):
                    val = m.group(1)
                    # 排除明显不是人话的（宏、格式化占位、单标识符）
                    if len(val) < 6 or not re.search(r"[a-z]{3}", val):
                        continue
                    hits[name] += 1
                    total += 1
                    top = os.path.relpath(p, root).split(os.sep)[0]
                    bydir[top] += 1
                    if len(samples[name]) < 6:
                        samples[name].append(f"{os.path.relpath(p, root)}: {val[:110]}")

    print("=== 写死、无法翻译的用户可见文本（引擎全量）===")
    for k, v in hits.most_common():
        print(f"  {k:20} {v}")
    print(f"  {'合计':20} {total}")
    print()
    print("=== 按顶层目录 ===")
    for d, c in bydir.most_common(15):
        print(f"  {c:5}  {d}")
    print()
    for k in samples:
        print(f"-- {k}")
        for s in samples[k][:5]:
            print("   ", s)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "engine/godot")
