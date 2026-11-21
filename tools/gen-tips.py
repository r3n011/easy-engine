"""把 defs/tips.zh.json 生成给网页用的 defs_tips.js。

文案只有一份（defs/tips.zh.json），网页和将来的其它前端都从这里取。
"""

import io
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "modules", "easyblocks", "defs", "tips.zh.json")
OUT = os.path.join(ROOT, "web", "app", "defs_tips.js")


def main():
    with io.open(SRC, encoding="utf-8") as f:
        data = json.load(f)
    blocks = data.get("blocks", {})

    # 输出成 JS 对象，键是引擎侧的积木 id
    js = {"blocks": blocks}
    payload = json.dumps(js, ensure_ascii=False, indent=0).replace("\n", "")

    text = (
        "/* 由 tools/gen-tips.py 生成，请不要手改。 */\n"
        "/* 源文件：modules/easyblocks/defs/tips.zh.json */\n"
        "window.EE_TIPS = " + payload + ";\n"
    )

    old = None
    if os.path.exists(OUT):
        with io.open(OUT, encoding="utf-8") as f:
            old = f.read()
    if old != text:
        with io.open(OUT, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("tips: 已更新 %s（%d 个积木）" % (OUT, len(blocks)))
    else:
        print("tips: 无变化（%d 个积木）" % len(blocks))


if __name__ == "__main__":
    main()
