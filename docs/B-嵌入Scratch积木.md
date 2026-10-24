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
| 积木覆盖 | 目前接了 **71 种** Scratch 积木。已覆盖运动/外观/控制/事件/侦测/运算/变量/列表 + 造型切换、声音、克隆体。还差：自制积木（带参数/返回值）、画笔/音乐等扩展 |
| 撤销重做 | 网页里能撤销，但引擎侧的节点树改动还没走 `EditorUndoRedoManager` |
| 自动挂载的撤销 | 第一次给节点写积木时会自动加一个 `BlockRunner` 子节点，这一步目前不进撤销栈 |
| 运行按钮 | 现在靠 Godot 自己的运行（F5）跑整个项目；以后可以加"只运行当前角色" |

---

## 造型 / 声音 / 克隆体（运行时）

这三样是 Scratch 小游戏最常用的，现在已经实现并验证。

### 语义怎么落到 Godot 上

| Scratch 概念 | Godot 里的对应 |
|---|---|
| **造型** | `AnimatedSprite2D` 的动画（按名字/序号/下一个切换）；若是 `Sprite2D`，就切图集的第几帧 |
| **声音** | 角色下面的 `AudioStreamPlayer` / `AudioStreamPlayer2D` 子节点（按名字找，找不到就用第一个） |
| **克隆体** | `duplicate()` 出一个同构子树，加上 `ee_clone` 标记，只启动「作为克隆体启动时」的脚本 |
| **删除此克隆体** | 只有带 `ee_clone` 标记的节点才会被删（不会误删原角色） |

### 验证结果

`test/features/` 里的程序：

```
当绿旗被点击
  将y坐标增加 10
  播放声音 (空) 等待播完
  换成 下一个造型
  重复执行 2 次 → 克隆 自己

当作为克隆体启动时
  将x坐标增加 100
```

无渲染跑出来的结果：

```
子节点数=4
Hero        x=0    y=10  帧=1     ← 造型从 0 切到 1
Hero_clone  x=100  y=10  帧=1     ← 克隆体跑了自己的帽子
Hero_clone2 x=100  y=10  帧=1     ← 第二个克隆体，名字自动去重
警告=["这个角色下面没有音频播放器，播不了声音："]   错误=[]
```

三个关键点都验证到了：

1. **造型真的切了**（帧 0 → 1）
2. **克隆体的帽子会跑，绿旗脚本不会重跑**（克隆体 y 仍是 10，不是 20）
3. **没有音频播放器时不卡死**（告警后继续往下执行，线程没被挂住）

### 顺手修的一个坑

`motion_bounce`（碰到边缘就反弹）在 scratch-blocks 里是**独立块**——没有上下的连接口。
我们的载入器如果给它写了 `<next>`，`domToWorkspace` 会直接抛
`Cannot read properties of null (reading 'isConnected')`，整段程序都加载不出来。
现在的处理是：转换时按连接口判断，接不上的抛出一条明确警告，而不是崩掉。

另外还踩了一个观感坑：积木刚画出来时如果容器尺寸没稳定，路径会短一截，
看起来像"积木被切掉了"。解法是**等字体就绪再建积木，并在之后一两帧强制重排一次**。

---

## 列表（运行时）

Scratch 的 11 个列表积木全部接通：清空、加入、删除（含"全部"）、插入、替换、
取第几项、项目数、第几项编号、是否包含、显示/隐藏（显示还没做 UI，数据照常记录）。

列表按角色存在运行器里（`HashMap<String, Array>`），下标语义照 Scratch：
**从 1 开始**，支持 `last` / `random` / `any`，越界自动夹到合法范围。

验证（`test/lists/`）：清空 → 加"苹果"、"香蕉" → 第 2 项插入"橙子" → 第 1 项替换成"苹果2" → 删第 3 项，结果是：

```
列表=["苹果2", "橙子"]   项目数=3   位置=3   存在=true   第二项=橙子
警告=[]  错误=[]
```

### 这一轮挖出的两个 Blockly 陷阱

1. **变量/列表必须先在工作区里声明**，否则 `domToFieldVariable_` 会自己按"普通变量"
   重建一个，类型对不上直接抛 `Variable type doesn't match this field`，**整段程序加载失败**。
   解法：载入前扫描程序里用到的变量/列表名，先 `workspace.createVariable(name, type)`。

2. **XML 里的变量字段必须带 `variabletype="list"`**，只写 `<field name="LIST">清单</field>`
   不够 —— Blockly 会按空类型处理，于是列表字段拿到一个普通变量，类型又不匹配。

3. **`getFieldValue()` 对变量字段返回的是内部 id，不是名字**。读回来必须用
   `field.getText()`，否则引擎侧收到的变量名是一串 `@V,O8mM9...` 这样的乱码，
   而且每加载一次都不一样，存进 `.tscn` 就彻底对不上了。

---

## 自制积木（运行 + 编译）

这是唯一需要**动编译器**的部分：用户造的积木没有静态定义，编译器得认。

### 程序格式（向后兼容，不升版本）

```json
{ "block": "core.procedure.define", "proccode": "倒数 %s", "params": ["数"],
  "inputs": { "BODY": { "stack": { ... } } } }

{ "block": "core.procedure.call", "proccode": "倒数 %s",
  "inputs": { "ARG0": { "value": 3 } } }

{ "block": "core.procedure.arg", "name": "数" }
```

调用参数固定用 `ARG0`、`ARG1`…（按位置），这样和 Scratch 的 `argumentids` 顺序一一对应。

### 编译器

`BlockProgram::compile()` 里对 `core.procedure.*` 特判，不走"查定义表"那条路：

- `define` → IR `procedures.define { proccode, params, body }`
- `call` → IR `procedures.call { proccode, args[] }`（参数按 ARG0.. 顺序编译）
- `arg` → IR `procedures.arg { name }`

### 运行时

- 启动时先把所有 `procedures.define` 收进 `procedures` 表（不启动线程）
- 调用时**在调用者作用域里**求值参数，然后压一层新作用域，再压函数体帧
- 帧关闭时弹掉作用域（新加了帧类型 `LOOP_PROC`）
- `procedures.arg` 从最内层作用域往外找

作用域用 `Vector<Dictionary>` 而不是 `Vector<HashMap>` —— 4.7 的 `HashMap` 不可拷贝，
塞不进 `Vector`。

### 验证：递归

`test/procedures/` 里的程序：

```
定义 倒数 (数)
  如果 (数) > 0 那么
    将y坐标增加 (数)
    倒数 ((数) - 1)

当绿旗被点击 → 倒数 3
```

无渲染跑出来 **y = 6**（3+2+1），无警告无错误。这条同时证明了：
参数作用域正确、递归正确、参数在调用者作用域求值正确。

### 网页端：Scratch 的 mutation

Scratch 把自制积木的元数据塞在 `<mutation>` 属性里：

```xml
<mutation proccode="倒数 %s" argumentids="[&quot;arg0&quot;]"
          argumentnames="[&quot;数&quot;]" argumentdefaults="[&quot;&quot;]" warp="false"/>
```

读写两边都要处理，而且参数名必须原样带过去（中文参数名、`%s`/`%b` 占位符都不能动）。
参数报告积木是 `argument_reporter_string_number`，值在 `VALUE` 字段里。

### 还没做的（要说清楚）

**「制作新的积木」按钮和参数编辑弹窗还没做。** 也就是说：
- 已经有自制积木的程序（比如导入的、或者用 JSON 写的）能完整显示、编辑、运行
- 但用户还**不能**在界面里从零新建一个自制积木

这块要做 Scratch 那个弹窗（输入名字、加参数、选"运行时不刷新屏幕"），是纯前端工作。



