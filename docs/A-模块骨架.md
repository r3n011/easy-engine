# A 阶段：让 Godot 引擎自己认得积木

> 目标（用户定的验收）：**在编译出来的 Godot 里，给某个节点挂一份积木程序，点运行，角色按积木动起来。**
>
> 状态：**已达成。**

---

## 一句话结论

积木不再是"套在 Godot 外面的另一个程序"，而是 `engine/godot/modules/easyblocks/` 里的一个**引擎模块**：

| 东西 | Godot 里的身份 | 意味着什么 |
|---|---|---|
| 积木定义 | 编译进二进制的 JSON（zlib 压缩） | 加积木只改一个 JSON，全引擎生效 |
| 一份积木程序 | `BlockProgram`（**Resource**） | 能存 `.tres`、进 `.tscn`、被检查器引用、跟着标准导出走 |
| 执行器 | `BlockRunner`（**Node**） | 挂在场景里，节点级运行，和引擎生命周期同步 |
| 编辑器界面 | `EditorPlugin`（`add_by_type<>` 注册） | 和 2D / 3D / 脚本并列，是编辑器的一部分 |

---

## 已经能跑的证据

### 1. 无渲染验证：位置精确到小数点

`test/easyblocks_smoke/program.json` —— 十次循环，每轮 x+5、y+3：

```json
{ "block": "core.control.repeat",
  "inputs": { "TIMES": { "value": 10 },
              "BODY": { "stack": { "block": "core.motion.change_x", "inputs": { "DX": { "value": 5 } },
                        "next": { "block": "core.motion.change_y", "inputs": { "DY": { "value": 3 } } } } } } }
```

运行结果：

```
EasyBlocks: 启动 1 个脚本，目标 Character
RESULT pos=(50.0, 30.0)
RESULT threads=0 errors=[] warnings=[]
```

10 × 5 = 50，10 × 3 = 30，**分毫不差**，且没有错误、没有残留线程。

### 2. 编辑器里真的有「积木」

截图：`docs/shot-module-editor.png`

底部面板出现 **积木** 标签，内容是「Easy Engine · 积木 / 积木 97 个 · op 92 个 · 分类 12 个」。

这验证的不是"画了个界面"，而是：**Godot 编辑器加载了我们模块注册的 EditorPlugin**。B 阶段把积木工作区填进这个面板即可，位置已经占住了。

---

## 落点与职责

```
modules/easyblocks/           ← 本仓库里的真源码（受版本管理）
├── config.py                 模块声明
├── SCsub                     构建脚本：构建时把 defs/*.json 打包成 C++ 头
├── register_types.cpp        往引擎注册类、单例、编辑器插件
├── block_library.{h,cpp}     积木/op 定义表（97 积木 + 92 op + 12 分类）
├── block_program.{h,cpp}     Resource：积木脚本 → IR
├── block_runner.{h,cpp}      Node：执行 IR（帧栈调度器）
├── values.{h,cpp}            值语义：转数字/转串/转布尔/比较/拼接
├── tools/gen_defs.py         定义打包器（构建时跑）
├── defs/*.json               积木与 op 定义（唯一事实来源）
└── editor/                   编辑器插件（A 阶段只占位，B 阶段填工作区）
```

`engine/godot/` 是 **可丢弃的构建目录**（Godot 浅克隆，被 `.gitignore` 忽略）。真源码在上面那个目录里，编译前同步：

```powershell
powershell -ExecutionPolicy Bypass -File tools\build-engine.ps1          # 同步 + 编译
powershell -ExecutionPolicy Bypass -File tools\sync-module.ps1           # 只同步
```

引擎树整个删掉重来，也不会丢代码。

---

## 关键设计决定

### 积木定义进二进制，不进文件系统

`defs/*.json` 在构建时被 zlib 压缩、以字节数组的形式编进可执行文件（这正是 Godot 自己嵌翻译文件的做法）。

好处：
- 运行时不依赖外部文件，导出游戏时不会漏带定义
- 二进制里只有一份权威定义，无法被外部改坏
- 体积可控（4.4 万字节的 JSON 压到约 9 千字节）

### 编译与执行分离

`BlockProgram::compile()` 把积木树按定义里的 `ir` 模板展开成 IR；`BlockRunner` 只认 IR。

于是：
- 编辑时可以随时重新编译、报错（`get_errors()` 返回可读信息）
- 运行时不再碰积木结构，快
- 以后加"代码转积木"只需要生成 `ir`，执行器一行都不用改

`target` 注入、参数默认值、分支展开，全部由定义里的 `ir` 模板 + `ops.*.json` 的 `args`/`defaults` 驱动，C++ 里没有硬编码任何一条积木的语义。

### 调度语义照抄 M2，一条没改

帧栈、循环每轮让步、`warp` 内不让步、单帧 op 预算、`warp` 超时强制让步 —— 和 `docs/format/EE-SCHEDULER.md` 定稿的完全一致。

M2 那 84 项语义测试仍然是这套 C++ 实现的验收基准（同语义、不同语言）。

---

## 踩过的坑（都写进代码注释了）

### 1. MSVC 按系统代码页读源码 —— 中文把字符串尾巴吃掉

生成的 `block_defs.gen.h` 是 UTF-8 无 BOM 时，MSVC 按 GBK 解释，某些中文字节会把字符串结尾的引号当成双字节字符的后半，导致字面量一直延伸到文件末尾，报 `C2026: 字符串太长`。

**规则：模块里所有 `.cpp`/`.h` 必须存成 UTF-8 **带 BOM**。** 已全部处理。

### 2. `String(const char*)` 是 Latin-1，不是 UTF-8

界面上的「积木」显示成 `ç§¯æ¨` —— 因为 UTF-8 字节被当成 Latin-1 解了。

**规则：C++ 里写中文一律 `String::utf8("积木")`。** 模块里 32 处已全部包好。

### 3. 编辑器里打开场景也会走 `_ready`

第一版一打开项目，角色就在编辑器里自己跑起来了。

**规则：`BlockRunner` 在 `is_editor_hint()` 时直接不启动。**

### 4. 参数补默认值会把 `target` 变成 null

`_instantiate` 会先给声明的参数补 `null`，于是"没写 target 就注入 `@self`"的判断失效，IR 里全是 `"target": null`，积木静默不生效。

**规则：判断不能只看 `has()`，还要看值是否为空。** 这个坑在 GDScript 版也踩过一次，两次都是同一个形状。

### 5. `-j15` 会把编译器内存打爆

24 GB 内存、同时开着 IDE 时，`-j15` 报 `C1060: 编译器堆空间不足`，`-j5` 也炸，`-j2` 稳定。

**规则：默认用 `-j2`，内存富裕再往上加。**

---

## A 阶段刻意没做的事（留给后面）

| 没做 | 为什么 |
|---|---|
| 积木工作区界面（画布/调色板/拖拽） | B 阶段，`runtime/editor/` 里已有 1400 行 GDScript 蓝本可移植 |
| 广播、克隆体、列表 | A 只验证"引擎认得积木并执行"，这些在 B/C 阶段按 M2 语义补齐 |
| 积木 ↔ 场景双向同步 | 依赖编辑器界面，B 之后 |
| 图形特效、代码逃生舱 | M3 已在 GDScript 版验证，C++ 移植排在 C 阶段 |

---

## 怎么自己验证一遍

```powershell
# 1. 编译（会先同步模块源码）
powershell -ExecutionPolicy Bypass -File tools\build-engine.ps1

# 2. 无渲染跑测试项目，应当输出 pos=(50.0, 30.0)
engine\godot\bin\godot.windows.editor.x86_64.exe --headless --path test\easyblocks_smoke

# 3. 看编辑器界面（环境变量会让「积木」面板自动切到前台）
$env:EASYBLOCKS_SHOW_PANEL="1"
powershell -ExecutionPolicy Bypass -File tools\run-demo.ps1 -EditorPath test\easyblocks_smoke -Out docs\shot-module-editor.png
```

---

## 下一步（B 阶段）

把 `runtime/editor/` 那套积木绘制与拖拽搬成 C++，填进已经占好的「积木」面板：

1. 调色板：读 `BlockLibrary` 的分类与积木，按分类分栏
2. 画布：六种形状（帽子 / C 形 / 报告 / 胶囊 / 布尔六边形 / 普通）自绘
3. 拖拽吸附：块间吸附、C 形内嵌、报告类进插槽
4. 与选中节点联动：选中 `Sprite2D` → 显示它挂的 `BlockProgram`
5. 点运行 → 走 `BlockRunner`（已通）
