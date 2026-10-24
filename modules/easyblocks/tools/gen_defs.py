"""把 defs/*.json 打包成压缩字节数组，嵌进 C++ 头文件。

为什么不直接塞原始字符串字面量：
  · MSVC 对超长字符串字面量有上限，跨行的 UTF-8 原文很容易踩到
  · 压缩后体积小、且完全不涉及源码编码问题
这正是 Godot 自己嵌翻译文件（.po）的做法。
"""

import json
import os
import zlib

HEADER = "block_defs.gen.h"
PER_LINE = 24


def _load(defs_dir, prefix):
    items = []
    if not os.path.isdir(defs_dir):
        return items
    for name in sorted(os.listdir(defs_dir)):
        if not (name.startswith(prefix + ".") and name.endswith(".json")):
            continue
        with open(os.path.join(defs_dir, name), encoding="utf-8") as f:
            raw = f.read()
        json.loads(raw)  # 先校验，免得把坏文件打进二进制
        items.append((name, raw))
    return items


def _emit(lines, symbol, items):
    n = len(items)
    lines.append("static const int _eb_%s_count = %d;" % (symbol, n))
    lines.append("")

    comp_sizes = []
    raw_sizes = []
    for i, (name, raw) in enumerate(items):
        data = raw.encode("utf-8")
        comp = zlib.compress(data, 9)
        comp_sizes.append(len(comp))
        raw_sizes.append(len(data))
        lines.append("// %s（%d -> %d 字节）" % (name, len(data), len(comp)))
        lines.append("static const unsigned char _eb_%s_%d[] = {" % (symbol, i))
        for j in range(0, len(comp), PER_LINE):
            lines.append(",".join(str(b) for b in comp[j:j + PER_LINE]) + ",")
        lines.append("};")
        lines.append("")

    # 索引表（0 个定义时也要能编译）
    lines.append("static const unsigned char *_eb_%s_data[%s] = {" % (
        symbol, str(n) if n > 0 else "1"))
    lines.append(",".join("_eb_%s_%d" % (symbol, i) for i in range(n)) or "nullptr")
    lines.append("};")
    lines.append("")
    lines.append("static const int _eb_%s_comp[%s] = {" % (symbol, str(n) if n > 0 else "1"))
    lines.append(",".join(str(x) for x in comp_sizes) or "0")
    lines.append("};")
    lines.append("")
    lines.append("static const int _eb_%s_raw[%s] = {" % (symbol, str(n) if n > 0 else "1"))
    lines.append(",".join(str(x) for x in raw_sizes) or "0")
    lines.append("};")
    lines.append("")


def generate(mod_dir):
    defs_dir = os.path.join(mod_dir, "defs")
    blocks = _load(defs_dir, "blocks")
    ops = _load(defs_dir, "ops")

    lines = [
        "// 由 tools/gen_defs.py 在构建时生成 —— 请不要手改。",
        "// 积木定义：" + "、".join(n for n, _ in blocks),
        "// op 定义：" + "、".join(n for n, _ in ops),
        "#pragma once",
        "",
    ]
    _emit(lines, "block_defs", blocks)
    _emit(lines, "op_defs", ops)

    text = "\n".join(lines)
    out = os.path.join(mod_dir, HEADER)

    old = None
    if os.path.exists(out):
        with open(out, "rb") as f:
            old = f.read().decode("utf-8-sig")
    if old != text:
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("easyblocks: 已更新 %s（积木定义 %d 个，op 定义 %d 个）"
              % (HEADER, len(blocks), len(ops)))
