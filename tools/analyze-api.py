"""分析 Godot 暴露给脚本的 API 规模，为"哪些能力无法用积木表达"提供数据依据。

数据来源：godot --headless --dump-extension-api 生成的 extension_api.json

用法: python tools/analyze-api.py [extension_api.json]
"""
import collections
import json
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "datadump/extension_api.json"

api = json.load(open(PATH, encoding="utf-8"))

classes = api.get("classes", [])
n_cls = len(classes)
n_method = sum(len(c.get("methods", [])) for c in classes)
n_prop = sum(len(c.get("properties", [])) for c in classes)
n_sig = sum(len(c.get("signals", [])) for c in classes)
n_enum = sum(len(c.get("enums", [])) for c in classes)
n_const = sum(len(c.get("constants", [])) for c in classes)
n_arg = sum(len(m.get("arguments", [])) for c in classes for m in c.get("methods", []))
n_ctor = sum(len(c.get("constructors", [])) for c in classes)

print("=== Godot 暴露给脚本的 API 总量 ===")
print(f"  类        : {n_cls}")
print(f"  方法      : {n_method}  (参数合计 {n_arg})")
print(f"  属性      : {n_prop}")
print(f"  信号      : {n_sig}")
print(f"  枚举      : {n_enum}")
print(f"  常量      : {n_const}")
print(f"  构造函数  : {n_ctor}")
print(f"  API 元素合计: {n_method + n_prop + n_sig + n_const}")

# 方法数最多的类：这些是"代码味"最重的
print()
print("=== 方法数最多的 25 个类 ===")
for c in sorted(classes, key=lambda c: -len(c.get("methods", [])))[:25]:
    print(f"  {len(c['methods']):5}  {c['name']}")

# 按名字前缀归类，看哪些子系统体量最大
print()
print("=== 按名字前缀归类（方法数 Top 20）===")
groups = collections.Counter()
for c in classes:
    m = re.match(r"([A-Z][a-z]+)", c["name"])
    key = m.group(1) if m else "?"
    groups[key] += len(c.get("methods", []))
for k, v in groups.most_common(20):
    print(f"  {v:6}  {k}*")

# 明确"必须写代码"的类是否存在于 API 里
print()
print("=== 本质属于「写代码」的类（存在即说明积木需要逃生舱）===")
WATCH = [
    "Shader", "ShaderMaterial", "ShaderInclude", "VisualShader",
    "RenderingDevice", "RenderingServer",
    "Thread", "Mutex", "Semaphore", "WorkerThreadPool",
    "GDExtension", "EditorPlugin", "EditorInspectorPlugin",
    "Resource", "AnimationTree", "AnimationNode", "AnimationNodeStateMachine",
    "RegEx", "JSON", "Expression", "SceneTreeTimer",
    "MultiplayerAPI", "MultiplayerPeer", "ENetMultiplayerPeer",
    "Mesh", "ArrayMesh", "SurfaceTool", "ImmediateMesh",
    "Noise", "FastNoiseLite", "Curve3D", "Path3D",
    "Basis", "Quaternion", "Transform2D", "Transform3D", "Projection",
    "Callable", "Signal", "StringName", "String", "PackedByteArray",
]
names = {c["name"]: c for c in classes}
for w in WATCH:
    c = names.get(w)
    if c:
        print(f"  {w:26} 方法 {len(c.get('methods', [])):5}  属性 {len(c.get('properties', [])):4}  信号 {len(c.get('signals', [])):3}")
    else:
        print(f"  {w:26} （未在 API 中）")

# 需要传入 Callable / 函数引用的方法：积木最难表达的东西
print()
print("=== 参数里含 Callable 的方法数（积木最难表达：把'函数'当参数传）===")
cnt = 0
samples = []
for c in classes:
    for m in c.get("methods", []):
        types = [a.get("type", "") for a in m.get("arguments", [])]
        if "Callable" in types:
            cnt += 1
            if len(samples) < 12:
                samples.append(f"{c['name']}.{m['name']}")
print(f"  合计: {cnt}")
for s in samples:
    print(f"    {s}")
