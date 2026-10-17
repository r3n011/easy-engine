"""给 provider 的 op 方法加上参数类型。

为什么不是把报错逐个消掉：给 ctx 标注成 OpContext 之后，ctx.get_list() 之类
就有了明确返回类型，`:=` 推断自然成立，而且 op 实现从此有了类型检查。
"""
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "runtime", "ee", "providers")

HEADER = '''const Values = preload("res://ee/values.gd")
const OpContext = preload("res://ee/op_context.gd")
'''

for name in ["core_ops.gd", "physics2d_ops.gd"]:
    path = os.path.join(ROOT, name)
    with open(path, encoding="utf-8") as f:
        t = f.read()

    # 1) 引入 OpContext 类型
    if "const OpContext" not in t:
        t = t.replace(
            'const Values = preload("res://ee/values.gd")\n',
            HEADER,
            1,
        )

    # 2) 给 op_* 方法的参数加类型
    t = re.sub(r"func (op_\w+)\(ctx, (_?op)\)", r"func \1(ctx: OpContext, \2: Dictionary)", t)
    t = re.sub(r"func (op_\w+)\(_ctx, (_?op)\)", r"func \1(_ctx: OpContext, \2: Dictionary)", t)

    # 3) 结果类型确实是 Variant 的局部变量，去掉推断
    t = re.sub(r"var (\w+) := (ctx\.eval\()", r"var \1 = \2", t)
    t = re.sub(r"var (\w+) := (runtime\.eval_expression\()", r"var \1 = \2", t)

    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(t)
    print(f"  {name} 已更新")
print("完成")
