"""权威验证：抽取 Godot 源码里所有"界面/属性文案"，与 .po 求差集。

依据 core/string/ustring.h 的真实签名：
    String TTR (const String &p_text, const String &p_context = "");
    String TTRN(const String &p_text, const String &p_text_plural, int p_n, const String &p_context = "");
    String RTR (const String &p_text, const String &p_context = "");
    String RTRN(const String &p_text, const String &p_text_plural, int p_n, const String &p_context = "");
    #define TTRC(m_value)  (m_value)     // C 字符串，需 TTRGET 才翻译
    #define PNAME(m_value) (m_value)     // 属性名  -> editor/translations/properties/*.po
    #define GNAME(m_value, m_prefix)      // 分组名  -> editor/translations/properties/*.po
    String DTR / DTRN(...)                // 类文档

用法:
  python tools/extract-ttr.py [engine目录]
"""
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from importlib import import_module

_po = import_module("po-stats")

SKIP_DIRS = {"thirdparty", "bin", ".git", "obj", "tests"}

# 函数式翻译入口：参数语义 (msgid, [msgid_plural], [context])
FUNCS = {"TTR", "RTR", "TTRN", "RTRN", "TTRC", "PNAME", "GNAME", "DTR", "DTRN", "ETR", "ETRN", "ATR"}
RE_CALL = re.compile(r"\b(" + "|".join(sorted(FUNCS, key=len, reverse=True)) + r")\s*\(")

# 各入口归属的 .po 文件类别
KIND_OF = {
    "PNAME": "property",
    "GNAME": "property",
    "ETR": "extractable",
    "ETRN": "extractable",
}

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "'": "'", "0": "\0"}


def strip_comments(text):
    """剔除 C/C++ 注释，但保护字符串字面量（文档注释里的示例会污染统计）。"""
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            quote = c
            out.append(c)
            i += 1
            while i < n:
                out.append(text[i])
                if text[i] == "\\" and i + 1 < n:
                    out.append(text[i + 1])
                    i += 2
                    continue
                if text[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        if c == "/" and i + 1 < n:
            if text[i + 1] == "/":
                while i < n and text[i] != "\n":
                    i += 1
                continue
            if text[i + 1] == "*":
                i += 2
                while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                    i += 1
                i += 2
                continue
        out.append(c)
        i += 1
    return "".join(out)


def unescape_cpp(s):
    out = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append(ESCAPES.get(s[i + 1], s[i + 1]))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


RE_STR = re.compile(r'\s*("(?:[^"\\]|\\.)*")\s*')


def literal_of(arg):
    """把参数解析成字符串字面量；动态拼接返回 None。

    支持 C++ 相邻字面量拼接: "foo" "bar" -> foobar
    """
    arg = arg.strip()
    toks = RE_STR.findall(arg)
    if not toks:
        return None
    rest = RE_STR.sub("", arg)
    if rest.strip():
        return None  # 含变量/运算符，动态串
    return "".join(unescape_cpp(t[1:-1]) for t in toks)


def split_args(text, start):
    """从 '(' 之后开始，按顶层逗号切分参数，返回 (args, end)"""
    args = []
    cur = []
    depth = 1
    in_str = False
    esc = False
    i = start
    while i < len(text):
        c = text[i]
        if in_str:
            cur.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
                cur.append(c)
            elif c in "([{":
                depth += 1
                cur.append(c)
            elif c in ")]}":
                depth -= 1
                if depth == 0:
                    args.append("".join(cur))
                    return args, i
                cur.append(c)
            elif c == "," and depth == 1:
                args.append("".join(cur))
                cur = []
            else:
                cur.append(c)
        i += 1
    return args, i


def scan(text):
    """产出 (kind, msgid, msgid_plural, context) 记录。

    kind: 'text'        -> editor/*.po
          'extractable' -> extractable/*.po   (ETR)
          'property'    -> properties/*.po    (PNAME / GNAME)
    """
    for m in RE_CALL.finditer(text):
        name = m.group(1)
        args, _end = split_args(text, m.end())
        lits = [literal_of(a) for a in args]
        lits = [l for l in lits if l]

        kind = KIND_OF.get(name, "text")

        if name in ("PNAME", "GNAME"):
            if lits:
                yield ("property", lits[0], None, "")
            continue

        if not lits:
            continue
        if name in ("TTRN", "RTRN", "DTRN", "ETRN"):
            # (单数, 复数, n, [context])
            if len(lits) >= 2:
                ctx = lits[2] if len(lits) >= 3 and len(args) >= 4 else ""
                yield (kind, lits[0], lits[1], ctx)
            continue
        # TTR / RTR / TTRC / DTR / ETR / ATR : (文案, [上下文])
        ctx = lits[1] if len(lits) >= 2 else ""
        yield (kind, lits[0], None, ctx)


def load_po(paths):
    """返回 {(kind, ctx, msgid)} 与 {path: 条目数}"""
    known = set()
    counts = {}
    for p in paths:
        if not os.path.isfile(p):
            continue
        norm = p.replace("\\", "/")
        if "properties" in norm:
            kind = "property"
        elif "extractable" in norm:
            kind = "extractable"
        else:
            kind = "text"
        entries, _h = _po.parse_po(p)
        for e in entries:
            known.add((kind, e.ctx, e.id))
            if e.plural:
                known.add((kind, e.ctx, e.plural))
        counts[p] = len(entries)
    return known, counts


def main(root):
    base = os.path.join(root, "editor", "translations")
    po_paths = [
        os.path.join(base, "editor", "zh_Hans.po"),
        os.path.join(base, "properties", "zh_Hans.po"),
        os.path.join(base, "extractable", "zh_Hans.po"),
    ]
    known, counts = load_po(po_paths)

    stats = collections.Counter()
    missing = collections.Counter()
    missing_ctx = collections.Counter()
    byfile = collections.Counter()
    n_calls = 0

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
            if not any(k in txt for k in FUNCS):
                continue
            rel = os.path.relpath(p, root)
            for kind, mid, plural, ctx in scan(strip_comments(txt)):
                n_calls += 1
                stats["property" if kind == "property" else "text"] += 1
                if (kind, ctx, mid) not in known:
                    missing[mid] += 1
                    missing_ctx[(ctx, mid)] += 1
                    byfile[rel] += 1
                if plural and (kind, ctx, plural) not in known:
                    missing[plural] += 1
                    missing_ctx[(ctx, plural)] += 1
                    byfile[rel] += 1

    print("=== 抽取到的文案调用 ===")
    print(f"  界面文案(TTR/RTR/TTRN...) : {stats['text']}")
    print(f"  属性/分组名(PNAME/GNAME)  : {stats['property']}")
    print(f"  合计                      : {n_calls}")
    print()
    print("=== 已有译文条目 ===")
    for f, n in counts.items():
        print(f"  {n:6}  {os.path.relpath(f, root)}")
    print(f"  {len(known):6}  含上下文去重后")
    print()
    print("=== 漏翻译（源码有标记，但 .po 里没有）===")
    print(f"  去重后: {len(missing_ctx)}      出现次数: {sum(missing.values())}")
    if missing_ctx:
        print()
        for (ctx, mid), c in missing_ctx.most_common():
            ctag = f"  [上下文: {ctx}]" if ctx else ""
            print(f"  x{c:<3} {mid[:110]!r}{ctag}")
        print()
        print("=== 涉及文件 ===")
        for f, c in byfile.most_common(20):
            print(f"  {c:5}  {f}")
    else:
        print("  ✅ 无 — 界面与属性文案已 100% 汉化")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "engine/godot")
