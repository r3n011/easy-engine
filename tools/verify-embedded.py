"""从生成的 translations.gen.cpp 里解出内嵌的 .po 内容，验证译文确实进了二进制。

构建时 editor_builders.make_translations 会把 .po 压缩成字节数组写进
*_translations.gen.cpp，运行时由 TranslationLoaderPO 解析。

用法: python tools/verify-embedded.py <gen.cpp> <要查找的字符串> [...]
"""
import re
import sys
import zlib


def extract(path, var_prefix=None):
    src = open(path, encoding="utf-8", errors="ignore").read()
    if var_prefix is None:
        # 自动识别：取第一个 xxx_translation_zh_Hans_compressed
        m0 = re.search(r"const unsigned char (_[A-Za-z0-9_]*_translation_zh_Hans_compressed)\[\]", src)
        if not m0:
            return None
        var_prefix = m0.group(1)
    m = re.search(
        r"inline constexpr const unsigned char " + re.escape(var_prefix) + r"\[\] = \{(.*?)\};",
        src,
        re.S,
    )
    if not m:
        return None
    nums = re.findall(r"\d+", m.group(1))
    return zlib.decompress(bytes(int(n) for n in nums))


def main():
    gen = sys.argv[1]
    needles = sys.argv[2:]
    data = extract(gen)
    if data is None:
        print("未找到 zh_Hans 数据块")
        return 1
    print(f"解出 {len(data)} 字节（.po 文本）")
    text = data.decode("utf-8")
    print(f"其中包含条目 {text.count('msgid ')} 条")
    rc = 0
    for n in needles:
        hit = n in text
        print(f"  {'命中' if hit else '缺失'}  {n[:70]!r}")
        if not hit:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
