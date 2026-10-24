# 方案 v2：把 Godot 本体改造成积木引擎

> **v1 的问题**：v1 把积木编辑器做成了"一个基于 Godot 的独立程序"（`runtime/` 那套）。
> 那不是"改 Godot"，是"用 Godot 写了个自己的 app"。
>
> **v2 的定位**：**产品 = 我们改过的 Godot 编辑器。** 用户打开的是 Godot（我们的构建），
> 里面多了一个「积木」工作区；积木是引擎里的**一等公民**（Resource / Node），
> 能挂到节点上、存进场景、跟着导出。

> **进度**：A 阶段（让引擎认得积木）**已完成** —— 模块已编进 Godot，
> 积木程序能驱动真实节点，编辑器里已有「积木」入口。
> 详见 [A-模块骨架.md](A-模块骨架.md)。下一步是 B 阶段（积木工作区界面）。

---

## 一、落点：改哪几个文件

```
engine/godot/                        ← 产品就是这一份源码编译出来的编辑器
├── modules/easyblocks/              ★ 新增引擎模块
│   ├── register_types.cpp           在编辑器里注册我们的 EditorPlugin：
│   │                                  EditorPlugins::add_by_type<EasyBlocksEditorPlugin>()
│   ├── block_library.{h,cpp}        积木定义注册表（读 defs/*.json）
│   ├── block_program.{h,cpp}         Resource：积木图 + 编译出的 IR（可存 .tres/.tscn）
│   ├── block_runner.{h,cpp}          Node：执行积木程序（挂在场景里）
│   ├── scheduler.{h,cpp}             调度器：线程/让步/warp/广播/克隆体（M2 语义原样搬）
│   ├── values.{h,cpp}                值语义（转换/比较/运算）
│   ├── ops/                          op 实现（运动/外观/控制/运算/变量/元积木…）
│   ├── bridge/                       与 Godot 节点、渲染、物理、输入对接
│   ├── defs/blocks.*.json            积木定义（随二进制分发）
│   └── editor/                       ★ 编辑器侧
│       ├── easy_blocks_editor_plugin.{h,cpp}  主屏幕 + 底部面板 + 选中节点联动
│       ├── block_draw.{h,cpp}                  积木形状（帽子/C 形/报告/布尔/缺口/凸榫）
│       ├── block_canvas.{h,cpp}                画布：拖拽、吸附、成串
│       └── palette.{h,cpp}                     调色板：分类与积木列表
└── editor/                          少量补丁：主屏幕登记、默认启用、品牌与精简
```

**为什么这就叫"基于 Godot 修改"**（而不是外挂）：

| | v1（已废弃） | v2 |
|---|---|---|
| 用户打开的 | 我写的 exe | **Godot 编辑器本体** |
| 积木是什么 | 我的 JSON 文件 | 引擎里的 `Resource` / `Node` |
| 积木存哪 | 我的 `.ee` | **`.tscn` / `.tres` 里**，和场景一起 |
| 导出 | 我的播放器 | **引擎标准导出**（exe/apk/web 都行） |
| 界面位置 | 另一个程序的窗口 | Godot 的主屏幕（与 2D/3D/Script 并列） |

依据：Godot 自己就是这么做内置功能的 —— `modules/csg`、`modules/multiplayer`、
`modules/navigation_2d` 都在 `register_types.cpp` 里用
`EditorPlugins::add_by_type<...>()` 往编辑器里加界面。

---

## 二、已有资产怎么处置（不浪费）

| 现有 | 去向 |
|---|---|
| `runtime/ee/defs/*.json` 积木定义（97 个） | ✅ 原样搬进 `modules/easyblocks/defs/` |
| `runtime/ee/registry.gd` 注册表与交叉校验 | → `block_library.cpp` |
| `runtime/ee/compiler.gd` 积木→IR | → `block_program.cpp` 的编译部分 |
| `runtime/ee/runtime.gd` / `thread.gd` 调度器 | → `scheduler.cpp`（**语义一条不改**） |
| `runtime/ee/values.gd` 值语义 | → `values.cpp` |
| `runtime/ee/providers/*.gd` op 实现 | → `ops/*.cpp` |
| `runtime/ee/bridge/godot_bridge.gd` 节点桥 | → `bridge/*.cpp` |
| `runtime/ee/shaders/sprite_effects.gdshader` | ✅ 直接搬 |
| `runtime/editor/*.gd` 积木绘制/拖拽（1400 行） | → **C++ 移植的蓝本**，逻辑与布局算法照搬 |
| `.ee` 格式与规格文档（3 份） | ✅ 概念保留；v2 起改成"积木程序资源 + 场景" |
| `runtime/player/` 独立播放器 | ❌ 废弃（引擎里直接跑） |
| `runtime/` 整个工程 | 降级为**测试床**，不再是产品 |

> M2 那 84 项语义测试是最大的既有资产：调度器搬进 C++ 之后，
> 用同一批用例在引擎里回归，保证"搬过去没搬错"。

---

## 三、分步落地（每步都能验收）

### A. 让引擎认得积木（本轮）
- `modules/easyblocks/` 骨架 + `register_types.cpp`
- `BlockProgram`（Resource）、`BlockRunner`（Node）、`BlockLibrary`（定义表）
- `BlockRunner` 里跑通最小调度器（等你把 GDScript 语义搬过来）
- 一个 `test/easyblocks_smoke.tscn`：给 `Sprite2D` 挂 `BlockProgram`，运行时按积木移动

**验收**：在**我们编译的 Godot** 里，把积木程序挂到节点上、点运行、角色按积木动。
此时还没有图形化编辑器（先用文本写积木程序），但"积木是引擎的一部分"这件事成立了。

### B. 把积木工作区搬进编辑器
- `EasyBlocksEditorPlugin`：注册一个主屏幕「积木」+ 一个底部面板
- 选中场景树里的节点 → 自动显示它的积木；编辑 → 写回 `BlockProgram`
- 把 `block_view/block_canvas/block_palette` 的三个逻辑移植成 C++：
  形状绘制、槽位、折行、拖拽、吸附、成串、垃圾桶
- 调色板由 `BlockLibrary` 生成（定义仍然只有一份）

**验收**：不启动任何外部程序，在 Godot 里拖积木 → 点运行 → 保存 → 重开项目，积木还在。

### C. 收口
- 新建项目模板（默认带一个舞台 + 一个角色 + 一组常用积木）
- **L1 简化模式**：用 `EditorFeatureProfile` 思路藏掉无关面板，只留角色/积木/舞台
- 汉化收尾（2597 条报错文本、1165 个枚举标签，见《汉化报告》）
- Windows 一键导出

---

## 四、代价（必须先认）

| 代价 | 说明 |
|---|---|
| **每次改动都要重编译** | 增量约 1–2 分钟；改头文件触发大范围重编时 5–10 分钟；全量 17 分钟 |
| **编辑器 UI 用 C++** | 比 GDScript 慢不少。1400 行 GDScript 移植成 C++ 是这一阶段的主要工作量 |
| **上游同步成本上升** | 我们的改动集中在 `modules/easyblocks/`（新目录，几乎不冲突）+ `editor/` 少量补丁，用 `patches/` 管理 |
| **调试链路更重** | 崩溃要看引擎栈；用 RelWithDebInfo + 日志 |

---

## 五、需要拍板的一件事

编辑器 UI 的写法：

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **A. C++ 直接写进模块**（推荐） | `modules/easyblocks/editor/*.cpp` | 真正的"改 Godot"；单一二进制；导出干净 | 慢，C++ 写 UI 费劲 |
| B. GDExtension + GDScript | 扩展形式挂编辑器插件 | 快得多，GDScript 迭代 | 严格说是"扩展"不是"改源码"；要额外分发插件文件 |

**我推荐 A。** 你的要求是"基于 Godot 修改"，那 UI 就该长在引擎里。

---

## 六、和 v1 的关系

- v1 的**规格与语义**（`.ee` 概念、IR 设计、调度语义、同步规则）**全部有效**，继续作为实现依据。
- v1 的**独立程序外壳**（`runtime/editor` 作为独立 app、`runtime/player`）**废弃**。
- 仓库仍然是同一个，不新开项目。
