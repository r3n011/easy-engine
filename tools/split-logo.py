"""把 logo 的 SVG 按区域拆成：完整版 / 图标 / 文字。

做法：**只改 viewBox，保留全部路径**。
为什么不把路径分给两边：logo 里有几条装饰路径纵向贯穿全图，硬分会把图形切坏；
改 viewBox 让渲染器自己裁，天然正确。

区域范围不是目测的：先用 Godot 渲染成 PNG、统计逐行墨迹分布算出图标与文字之间
真正的空白带和各自的像素范围（见 runtime/tools/find-split.gd），再传进来。

用法:
  python tools/split-logo.py <输入.svg> <输出目录> --icon x0,y0,x1,y1 --text x0,y0,x1,y1
"""
import os
import re
import sys


def parse_box(s):
    v = [float(x) for x in s.split(",")]
    return (v[0], v[1], v[2], v[3])


def union(a, b):
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def write_variant(src_text, out_path, box, pad, scale=1.0):
    x0, y0, x1, y1 = box
    x0 -= pad
    y0 -= pad
    x1 += pad
    y1 += pad
    w = (x1 - x0) * scale
    h = (y1 - y0) * scale
    # 换掉外层 svg 的 width/height/viewBox，路径原样保留
    text = re.sub(r'<svg[^>]*>',
                  f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" height="{h:.0f}" '
                  f'viewBox="{x0:.2f} {y0:.2f} {x1 - x0:.2f} {y1 - y0:.2f}">',
                  src_text, count=1)
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print(f"  {os.path.basename(out_path)}: {w:.0f} x {h:.0f}")


def main():
    args = sys.argv[1:]
    src = args[0]
    outdir = args[1]
    icon_box = text_box = None
    i = 2
    while i < len(args):
        if args[i] == "--icon":
            icon_box = parse_box(args[i + 1])
            i += 2
        elif args[i] == "--text":
            text_box = parse_box(args[i + 1])
            i += 2
        else:
            i += 1

    if icon_box is None or text_box is None:
        print("需要 --icon 与 --text 两个范围")
        sys.exit(2)

    src_text = open(src, encoding="utf-8").read()
    os.makedirs(outdir, exist_ok=True)
    print("输出：")
    write_variant(src_text, os.path.join(outdir, "logo-full.svg"), union(icon_box, text_box), 8)
    write_variant(src_text, os.path.join(outdir, "logo-icon.svg"), icon_box, 6, 2.0)
    write_variant(src_text, os.path.join(outdir, "logo-text.svg"), text_box, 6, 2.0)


if __name__ == "__main__":
    main()
