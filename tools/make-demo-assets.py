"""生成演示项目用的图片素材（纯 Python 写 PNG，不需要任何第三方库）。

为什么自己画：演示要能一键复现，就不能依赖外部素材文件的下载。
用法: python tools/make-demo-assets.py
"""
import math
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "runtime", "tests", "assets")


def write_png(path, w, h, px):
    """px[y][x] = (r,g,b,a)"""
    raw = bytearray()
    for row in px:
        raw.append(0)  # filter: none
        for p in row:
            raw += bytes(p)
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    print(f"  {os.path.relpath(path, os.path.join(OUT, '..', '..', '..'))}: {w}x{h}")


def blend(dst, src):
    a = src[3] / 255.0
    return tuple(int(dst[i] * (1 - a) + src[i] * a) for i in range(3)) + (255,)


def blank(w, h, color=(0, 0, 0, 0)):
    return [[color for _ in range(w)] for _ in range(h)]


def disc(px, cx, cy, r, color):
    for y in range(len(px)):
        for x in range(len(px[0])):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if d <= r:
                # 边缘柔化，避免锯齿太硬
                edge = min(1.0, max(0.0, r - d))
                c = (color[0], color[1], color[2], int(color[3] * edge))
                px[y][x] = blend(px[y][x], c)


def rect(px, x0, y0, x1, y1, color):
    for y in range(max(0, y0), min(len(px), y1)):
        for x in range(max(0, x0), min(len(px[0]), x1)):
            px[y][x] = color


def make_apple():
    w = h = 40
    px = blank(w, h)
    disc(px, 20, 24, 14, (225, 55, 55, 255))      # 果身
    disc(px, 15, 19, 5, (255, 130, 130, 160))     # 高光
    rect(px, 19, 6, 22, 12, (110, 75, 45, 255))   # 果柄
    rect(px, 22, 7, 30, 11, (70, 165, 70, 255))   # 叶子
    write_png(os.path.join(OUT, "apple.png"), w, h, px)


def make_basket():
    w, h = 80, 44
    px = blank(w, h)
    for y in range(h):
        t = y / (h - 1)
        half = 36 - 10 * t                      # 上宽下窄
        x0, x1 = int(40 - half), int(40 + half)
        shade = int(150 - 45 * t)
        rect(px, x0, y, x1, y + 1, (shade, int(shade * 0.62), int(shade * 0.30), 255))
    for x in range(6, w, 12):                   # 编织纹
        rect(px, x, 6, x + 2, h - 2, (95, 60, 28, 120))
    rect(px, 2, 2, w - 2, 8, (120, 80, 40, 255))
    write_png(os.path.join(OUT, "basket.png"), w, h, px)


def make_background():
    w, h = 480, 360
    px = blank(w, h)
    for y in range(h):
        sky = y / (h - 1)
        for x in range(w):
            px[y][x] = (int(120 + 90 * sky), int(180 + 50 * sky), int(245 - 20 * sky), 255)
    ground = 300
    rect(px, 0, ground, w, h, (95, 175, 95, 255))
    rect(px, 0, ground, w, ground + 4, (70, 140, 70, 255))
    disc(px, 400, 60, 28, (255, 245, 190, 255))  # 太阳
    write_png(os.path.join(OUT, "bg.png"), w, h, px)


if __name__ == "__main__":
    print("生成演示素材：")
    make_apple()
    make_basket()
    make_background()
