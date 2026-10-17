"""把补翻的界面文案写入 Godot 的 .po 文件。

用法:
  python tools/zh-apply.py [--dry-run] [--hant] [translations.json] [engine目录]

  --hant  同时写入繁体 zh_Hant.po（默认只写简体 zh_Hans.po）
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module

_po = import_module("po-stats")

TARGETS = {
    "text": ("editor", "zh_Hans.po"),
    "extractable": ("extractable", "zh_Hans.po"),
    "property": ("properties", "zh_Hans.po"),
}


def po_quote(s, indent=""):
    """把字符串格式化成 PO 的引号形式（含换行时用多行拼接）。"""
    if "\n" not in s:
        return f'{indent}"{_esc(s)}"'
    parts = s.split("\n")
    lines = [f'{indent}""']
    for i, p in enumerate(parts):
        tail = "\\n" if i < len(parts) - 1 else ""
        lines.append(f'{indent}"{_esc(p)}{tail}"')
    return "\n".join(lines)


def _esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\t", "\\t")


def existing_keys(path):
    entries, _h = _po.parse_po(path)
    return {(e.ctx, e.id) for e in entries}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    hant = "--hant" in sys.argv
    trans_path = args[0] if args else "tools/zh-translations.json"
    root = args[1] if len(args) > 1 else "engine/godot"

    with open(trans_path, encoding="utf-8") as f:
        trans = json.load(f)

    base = os.path.join(root, "editor", "translations")
    by_file = {}
    for t in trans:
        sub, fname = TARGETS[t["kind"]]
        by_file.setdefault((sub, fname), []).append(t)

    total_added = 0
    total_skipped = 0

    for (sub, fname), items in sorted(by_file.items()):
        locales = ["zh_Hans.po"] + (["zh_Hant.po"] if hant else [])
        for loc in locales:
            path = os.path.join(base, sub, loc)
            if not os.path.isfile(path):
                print(f"  跳过不存在的文件: {path}")
                continue
            known = existing_keys(path)
            added = []
            skipped = []
            for t in items:
                key = (t["context"], t["msgid"])
                if key in known:
                    skipped.append(t["msgid"])
                    continue
                added.append(t)
                known.add(key)

            print(f"\n=== {os.path.relpath(path, root)} ===")
            print(f"  待写入 {len(added)} 条，已存在跳过 {len(skipped)} 条")
            if skipped:
                for s in skipped[:5]:
                    print(f"    (已存在) {s[:70]!r}")

            if not added or dry:
                if dry and added:
                    print("  --dry-run，未写入。前 3 条预览：")
                    for t in added[:3]:
                        print(f"    {t['msgid'][:60]!r} -> {t['msgstr'][:60]!r}")
                total_skipped += len(skipped)
                continue

            with open(path, "r", encoding="utf-8") as f:
                body = f.read()
            if not body.endswith("\n"):
                body += "\n"

            chunks = []
            for t in added:
                block = []
                if t["context"]:
                    block.append(f'msgctxt "{_esc(t["context"])}"')
                block.append("msgid " + po_quote(t["msgid"]))
                block.append("msgstr " + po_quote(t["msgstr"]))
                chunks.append("\n".join(block))

            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(body + "\n" + "\n\n".join(chunks) + "\n")

            print(f"  已写入 {len(added)} 条")
            total_added += len(added)
            total_skipped += len(skipped)

    print(f"\n合计写入 {total_added} 条，跳过（已存在）{total_skipped} 条")
    if dry:
        print("(dry-run 模式，未改动文件)")


if __name__ == "__main__":
    main()
