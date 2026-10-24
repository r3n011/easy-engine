# B 阶段：把 Scratch 的积木编辑器嵌进 Godot

> **背景**：A 阶段做出来的原生积木界面（`runtime/editor/` 那套 GDScript，以及 C++ 移植的方向）
> 用户看了直说"复刻的不好看"。
>
> **决定**：不再自己画积木，**直接用 Scratch 的渲染内核**（scratch-blocks），
> 嵌入 Godot 编辑器的「积木」面板。
>
> 状态：**已嵌入并跑通，截图 `docs/shot-webview-editor.png`。**
> 还差"积木数据 ↔ 引擎"的桥（见文末）。

---

## 为什么这么改，代价是什么

用户的原话是"直接嵌入这个 scratch 的界面到 godot 里面"。要做，就得说清代价：

| 项 | 说明 |
|---|---|
| 渲染方式 | Godot 4 **没有**内嵌网页的节点。用 WebView2（Windows 自带 Edge 内核）起一个**原生子窗口**，叠在编辑器上，由我们跟着面板的位置/大小/显隐同步 |
| 平台 | 编辑器界面目前**只有 Windows**。Mac/Linux 以后另做（要么 CEF，要么接受没有网页版积木） |
| 边界 | 它不在 Godot 的控件树里：Godot 自己截的图截不到那块；Godot 的弹出菜单如果压在它上面会被遮住 |
| 数据 | **积木数据仍然存在 `BlockProgram` 资源里**（进 `.tscn`），网页只是"编辑时的界面"。导出的游戏里没有网页 |

最后一条是关键：我们没有因为嵌入网页而放弃"积木是引擎一等公民"。

---

## 现在长什么样

```
Godot 编辑器窗口
├── 场景 / 检查器 / 文件系统 ……（原生）
└── 底部面板  [输出] [调试器] [音频] [动画] [着色器编辑器] [积木] ← 我们的
                                    └── WebView2 子窗口
                                          └── https://easyblocks.local/index.html
                                                └── scratch-blocks（Scratch 3 原版渲染器）
```

- 积木形状、缺口、C 形、帽子、报告、布尔六边形 —— 全部由 Scratch 自己的渲染器画
- 配色、字重、拖拽吸附、垃圾桶 —— 和 Scratch 完全一致
- 中文 —— 用 Scratch 官方 `msg/scratch_msgs.js` 的 `zh-cn`（`Blockly.ScratchMsgs.setLocale`）

---

## 落点

```
web/app/                                   ← 积木工作区网页（提交进仓库，3.6MB）
├── index.html                             注入 Blockly、装工具箱、跑示例
└── vendor/scratch-blocks/
    ├── scratch-blocks.js                  Scratch 3 原版渲染器（vertical 版）
    ├── scratch_msgs.js                    官方多语言（含 zh-cn）
    ├── default_toolbox.js                 官方分类与积木清单
    ├── media/                             图标与光标
    └── LICENSE / TRADEMARK                Apache-2.0 + 商标声明

modules/easyblocks/editor/
├── easy_blocks_web_view.{h,cpp}           WebView2 宿主控件（Win32 子窗口 + COM）
└── easy_blocks_editor_plugin.{h,cpp}      「积木」面板，里面放上面的控件

tools/
├── fetch-webview2.ps1                     拉 WebView2 SDK（不入库）
├── sync-module.ps1                        模块源码 → 引擎树
└── build-engine.ps1                       拉 SDK → 同步 → 编译 → 复制网页与 DLL 到 bin
```

运行时资源（都在 `bin/`，由 `build-engine.ps1` 放好）：

```
bin/godot.windows.editor.x86_64.exe
bin/WebView2Loader.dll         WebView2 加载器（动态加载，不参与链接）
bin/easyblocks_web/            积木工作区网页
```

---

## 实现要点（踩过的坑）

### 1. 静态库链接被 SCons 改写名字

`env.Append(LIBS=["WebView2LoaderStatic"])` 会被 Godot 的构建系统改成
`WebView2LoaderStatic.windows.editor.x86_64.lib`；把 `.lib` 全路径塞进 `LINKFLAGS`
又报"找不到文件"（路径存在也会报）。

**做法：不链接，改成动态加载** `WebView2Loader.dll`（`LoadLibraryW` + `GetProcAddress`
拿 `CreateCoreWebView2EnvironmentWithOptions`）。微软官方两种集成方式之一，最省事。

### 2. 这个 Windows SDK 的 WRL 里没有 `Callback`

`Microsoft::WRL::Callback<...>(lambda)` 在 10.0.26100 的 `wrl/implements.h` 里没有。
自己写了一个 `EERefCounted<TInterface>` 模板 + 四个具体 handler（环境/控制器/消息/导航），
比依赖 WRL 内部实现更可控。

### 3. `DisplayServer` 的枚举搬到了 `DisplayServerEnums`

4.7 里是 `DisplayServerEnums::WINDOW_HANDLE`、`DisplayServerEnums::MAIN_WINDOW_ID`，
不再是 `DisplayServer::WINDOW_HANDLE`。

### 4. `robocopy /MIR` 会把引擎树里"手写的新文件"删掉

`sync-module.ps1` 用 `/MIR` 让引擎树严格等于仓库。
所以**任何改动都只能写在 `modules/easyblocks/` 下**，写在 `engine/godot/modules/easyblocks/`
会在下次同步时被删——这个坑踩过一次，丢了一个文件。

### 5. 网页资源要能加载相对路径和 ES 模块

用 `ICoreWebView2_3::SetVirtualHostNameToFolderMapping("easyblocks.local", <目录>, ALLOW)`
把本地目录映射成一个"网站"，然后 `Navigate("https://easyblocks.local/index.html")`。
比 `file://` 干净，也不会有 CORS 问题。

### 6. 每帧 `SetWindowPos` 会闪

只在面板矩形**真的变了**才动窗口（`Impl::rect` 缓存上一次的值）。

---

## 桥：接通了（B2）

现在网页和引擎是**双向**的：

```
选中节点 / 打开场景
      │  BlockProgram.scripts
      ▼
  eeLoadProgram(program)          ← 引擎调网页：把积木程序画成 Scratch 积木
      │
   用户拖积木
      │  250ms 防抖
      ▼
  postMessage({type:'program'})   →  引擎：写进 BlockProgram → compile() → IR
```

验证方式和结果（`EASYBLOCKS_DEBUG=1` 时能看到日志）：

```
积木桥：节点=Main 脚本=1 段
积木桥：已保存到 Main，1 段脚本，IR 1 条
积木往返校验：网页回显 1 段，编译 通过
```

然后模拟"用户把重复次数从 10 改成 7"，引擎侧的 IR 立刻变成：

```json
{"op":"control.repeat","times":7.0,"body":[...]}
```

`times` 从 `10.0` 变成 `7.0` —— **网页里的编辑确实写进了引擎**。截图 `docs/shot-bridge.png` 里可以看到"重复执行 7 次"，以及标题栏的 `main(*)`（场景被标记为已修改）。

### 积木怎么对应

`web/app/bridge.js` 里一张表，一行一条：

```js
{ s: 'motion_movesteps', e: 'core.motion.move_steps', inputs: { STEPS: 'STEPS' } }
{ s: 'looks_show',       e: 'core.looks.set_visible',  const: { MODE: 'show' } }
{ s: 'event_whenflagclicked', e: 'core.event.when_flag_clicked', nextFrom: 'BODY' }
```

- `s` Scratch 的积木类型，`e` 我们的积木 id
- `const` 处理"同一个积木的不同形态"（显示/隐藏、右转/左转）
- `fields` / `inputs` / `substack` 对应三种数据：下拉框、值槽、语句槽
- `nextFrom` 专门处理帽子积木（下面那串在 Scratch 里是 `next` 连接，在我们格式里是 `BODY`）

加一个新积木的支持 = 加一行 + 在 C++ 里实现对应的 op。没加映射的积木会被**跳过并警告**，不会静默吞掉：

```
WARNING: 这些积木暂时还不支持，已跳过：looks_switchcostumeto
```

### 又踩了三个坑

1. **连续工具箱会把分类里的积木画在主工作区。** `getTopBlocks()` 一开始把工具箱的积木也当成了用户程序，
   于是"每一帧都多出几段脚本"。用 `b.isInFlyout` 和事件里的 `workspaceId` 过滤掉。
2. **影子积木（数字框/文本框）不是积木。** `getInputTargetBlock()` 拿到的是 shadow，
   要读它的字段值当普通字面量，不能递归当积木转换。
3. **帽子积木的形状不一样。** Scratch 的帽子下面接 `next`，我们的格式里是 `BODY` 参数。
   漏了这条，载入后就只剩一个孤零零的「当绿旗被点击」。

---

## 还没做的

| 项 | 说明 |
|---|---|
| 积木覆盖 | 目前接了 52 种 Scratch 积木（运动/外观/控制/事件/侦测/运算/变量）。造型、声音、克隆、自制积木还没接 |
| 撤销重做 | 网页里能撤销，但引擎侧的节点树改动还没走 `EditorUndoRedoManager` |
| 自动挂载的撤销 | 第一次给节点写积木时会自动加一个 `BlockRunner` 子节点，这一步目前不进撤销栈 |
| 运行按钮 | 现在靠 Godot 自己的运行（F5）跑整个项目；以后可以加"只运行当前角色" |

