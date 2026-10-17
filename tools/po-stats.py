"""精确解析 Godot 的 .po 文件，统计翻译完成度。

正确处理 PO 的全部语义：msgctxt / msgid_plural / msgstr[N] / fuzzy / obsolete。

用法:
  python tools/po-stats.py <文件或目录> [...]
"""
import os
import re
import sys

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}


def unquote(s):
    s = s.strip()
    if s.startswith('"') and s.endswith('"') and len(s) >= 2:
        s = s[1:-1]
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            out.append(ESCAPES.get(s[i + 1], s[i + 1]))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


class Entry:
    __slots__ = ("ctx", "id", "plural", "strs", "plain", "flags", "obsolete", "line_no")

    def __init__(self, line_no):
        self.ctx = ""
        self.id = None
        self.plural = None
        self.strs = {}        # n -> msgstr[n]
        self.plain = None     # msgstr (非复数条目)
        self.flags = []
        self.obsolete = False
        self.line_no = line_no

    @property
    def key(self):
        return (self.ctx, self.id)

    def nplurals_needed(self):
        # 复数条目需要几个 msgstr
        return 1 if self.plural is not None else 0

    def is_translated(self):
        if self.plural is not None:
            return all(self.strs.get(n, "").strip() for n in range(self.nplurals_needed()))
        return bool(self.plain and self.plain.strip())


def parse_po(path):
    """返回 (entries, header_dict)。obsolete 条目（#~）会被跳过。"""
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().split("\n")

    entries = []
    cur = None
    mode = None
    obs_run = False

    def flush():
        nonlocal cur
        if cur is not None and cur.id is not None and not cur.obsolete:
            entries.append(cur)
        cur = None

    for idx, raw in enumerate(lines):
        s = raw.rstrip("\r")
        if s.startswith("#~"):
            if not obs_run:
                flush()
                cur = Entry(idx)
                cur.obsolete = True
                obs_run = True
            body = s[2:].lstrip()
            # 保守处理：obsolete 块内部不再解析内容
            continue
        obs_run = False

        if s.startswith("#,"):
            if cur is None:
                cur = Entry(idx)
            cur.flags += [t.strip() for t in s[2:].split(",") if t.strip()]
            continue
        if s.startswith("#"):
            continue
        if s.startswith("msgctxt "):
            # PO 里 msgctxt 出现在 msgid 之前，属于"新条目"的开始：
            # 必须先结束上一条，否则上下文会被错位绑定到上一条上。
            if cur is None or cur.id is not None:
                flush()
                cur = Entry(idx)
            cur.ctx = unquote(s[8:])
            continue
        if s.startswith("msgid_plural "):
            if cur is None:
                cur = Entry(idx)
            cur.plural = unquote(s[13:])
            mode = "plural_id"
            continue
        if s.startswith("msgid "):
            # 若当前条目已由 msgctxt 开了头（id 尚为空），则复用而不是新建
            if cur is not None and cur.id is not None:
                flush()
            if cur is None:
                cur = Entry(idx)
            cur.id = unquote(s[6:])
            mode = "id"
            continue
        if s.startswith("msgstr["):
            m = re.match(r"msgstr\[(\d+)\]\s*(.*)", s)
            if cur is not None and m:
                cur.strs[int(m.group(1))] = unquote(m.group(2))
            mode = "str_n"
            continue
        if s.startswith("msgstr "):
            if cur is None:
                cur = Entry(idx)
            cur.plain = unquote(s[7:])
            mode = "str"
            continue
        if s.startswith('"'):
            if cur is None:
                continue
            piece = unquote(s)
            if mode == "id":
                cur.id += piece
            elif mode == "plural_id":
                cur.plural += piece
            elif mode == "str":
                cur.plain = (cur.plain or "") + piece
            elif mode == "str_n":
                n = max(cur.strs) if cur.strs else 0
                cur.strs[n] = cur.strs.get(n, "") + piece
            continue
    flush()

    header = {}
    for e in entries:
        if e.id == "":
            for line in (e.plain or "").split("\n"):
                if ":" in line:
                    k, v = line.split(":", 1)
                    header[k.strip()] = v.strip()
            break
    real = [e for e in entries if e.id]
    return real, header


def report(path, show=0):
    entries, header = parse_po(path)
    total = len(entries)
    fuzzy = [e for e in entries if "fuzzy" in e.flags]
    todo = [e for e in entries if not e.is_translated()]
    done = total - len(todo)
    pct = (done / total * 100) if total else 100.0
    nplurals = header.get("Plural-Forms", "?")

    print(f"\n=== {os.path.basename(path)} ===")
    print(f"  路径        : {path}")
    print(f"  总条目      : {total}")
    print(f"  已翻译      : {done}  ({pct:.2f}%)")
    print(f"  未翻译      : {len(todo)}")
    print(f"  其中 fuzzy  : {len(fuzzy)}")
    print(f"  复数规则    : {nplurals[:80]}")
    if show and todo:
        print(f"  --- 未翻译条目（前 {show} 条）---")
        for e in todo[:show]:
            ctx = f"[{e.ctx}] " if e.ctx else ""
            plural = f"  (复数: {e.plural})" if e.plural else ""
            print(f"    L{e.line_no} {ctx}{e.id}{plural}")
    return {"path": path, "total": total, "todo": todo, "done": done, "pct": pct, "fuzzy": fuzzy}


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        args = ["editor/translations/editor/zh_Hans.po"]
    summary = []
    for t in args:
        if os.path.isdir(t):
            for root, _dirs, files in os.walk(t):
                for fn in sorted(files):
                    if fn.endswith(".po"):
                        summary.append(report(os.path.join(root, fn)))
        else:
            summary.append(report(t, show=60))

    if len(summary) > 1:
        print("\n\n=== 汇总 ===")
        print(f"{'文件':<52}{'条目':>8}{'未翻译':>8}{'完成度':>10}")
        for s in summary:
            print(f"{os.path.relpath(s['path']):<52}{s['total']:>8}{len(s['todo']):>8}{s['pct']:>9.2f}%")
        print(f"\n未翻译合计: {sum(len(s['todo']) for s in summary)}")
