# Easy Engine

**把 Godot 的能力，用 Scratch 积木的方式暴露出来让人编程。**

定位不是"让 Godot 跑 Scratch 项目"，而是**积木 = Godot 的可视化编程语言**：让只会 Scratch 的人，用熟悉的积木直接指挥 Godot 做出可发布的游戏。

详细技术方案见 **[docs/PLAN.md](docs/PLAN.md)**。

---

## 架构一句话

```
自研编辑器（fork scratch-gui）
      ↓  .ee 项目文件（积木图 + 节点树 + 资源）
    IR 编译
      ↓
Godot 原生运行时（调度器 + 节点桥）→ 导出 Windows .exe
```

## 目录结构

```
ee\
├── engine\godot\            Godot 4.7.2-stable 源码（已验证可构建）
├── scratch\
│   ├── Gandi-IDE\           Gandi 开源组件（参考资料）
│   └── TurboWarp\           scratch-gui（编辑器基座）/ scratch-vm（调度器参考）
├── tools\
│   ├── setup-vswhere.ps1    修复 MSVC 探测（换机器必跑一次）
│   └── analyze-sb3.ps1      统计 sb3 积木用量
└── docs\PLAN.md             技术方案（定稿）
```

## 已定的四个决策

| 决策 | 结论 |
|---|---|
| 创作端 | fork `scratch-gui` 自建编辑器（编辑器开源，GPL-3.0） |
| 执行层 | Godot 原生 IR 解释器（不是内嵌 JS） |
| 平台 | Windows 桌面优先 |
| 兼容性 | **不兼容社区 .sb3**；核心任务是"把 Godot 改为积木编程" |

## 快速开始

```powershell
# 1) 修复 C++ 工具链探测（只需一次）
powershell -File .\tools\setup-vswhere.ps1

# 2) 构建 Godot
cd engine\godot
python -m SCons platform=windows target=editor arch=x86_64 accesskit=no d3d12=no -j15
# 产物：engine\godot\bin\godot.windows.editor.x86_64.exe

# 3) 查看某个 Scratch 项目用了多少积木
..\..\tools\analyze-sb3.ps1 -Path .\some-game.sb3
```

## Godot 汉化

Godot 4.7.2 的简体中文界面**官方本来就基本完整**（6420 条编辑器文案 + 4300 条属性名 + 73 条导出文案，均为 100%）。

我做的不是"从头翻译"，而是用源码级差集找出**真正会漏出英文的 98 条**并补掉，现已清零：

| 文件 | 新增 | 内容 |
|---|---|---|
| `editor/translations/editor/zh_Hans.po` | 12 | 导出面板帮助文本、`[b]Hold Shift:[/b]` 系列提示等 |
| `editor/translations/extractable/zh_Hans.po` | 86 | 文件对话框、取色器、图形节点、确认框 |

完整报告见 **[docs/汉化报告.md](docs/汉化报告.md)**，含两个更深的坑：
- **2597 条写死的报错/警告文本**永远无法通过 .po 翻译（这才是"中文界面蹦英文"的主要来源）
- **中文字体**只认 `Noto Sans CJK SC`，Windows 上装的是 `Noto Sans SC`，匹配不上会退回老旧的 `DroidSansFallback`

```powershell
python tools\extract-ttr.py engine\godot   # 权威差集：源码文案 ↔ .po
python tools\zh-todo.py engine\godot       # 筛出真·界面漏翻
python tools\zh-apply.py                   # 回填（自动跳过已存在）
```

## M1 进展：格式与 IR 已定稿

`.ee` 项目格式、IR 规范、积木↔场景同步规则**已定稿**，编译管线**已跑通**：

```powershell
powershell -File tools/test-runtime.ps1     # 一条命令跑完 M1 全部验收
```

```
1. 定义注册表   扩展 2 个，积木 95 个，op 95 个；错误 0
2. 示例项目校验  节点 2 个，脚本 3 个；（无问题）
3. IR 回归      与基准一致（5090 字节）
M1 全部验收通过。
```

### 扩展性是怎么落到格式里的（这是本次的重点）

| 约束 | 做法 | 不这么做会怎样 |
|---|---|---|
| **IR 以后要改，老项目不能坏** | `.ee` 里**只存积木 id，不存 opcode**；opcode 由积木定义映射 | 每次改 IR 都要写一批转换脚本，越写越乱 |
| **加积木不能改引擎代码** | 积木与 op 全**数据驱动**（`defs/*.json`），文件名前缀决定扩展归属 | 社区无法扩展，我们自己也慢 |
| **旧版工具不能抹掉新字段** | 加载器**从不重建字典**，只在原始字典上读写 | 用户用旧版打开新项目、一保存，新功能全没了 |
| **Godot 升级不能静默搞坏项目** | 记录 `godotApiVersion` + API 改名映射表 | 每次 Godot 大版本升级都坏一批项目 |
| **格式升级不能写 N² 个转换器** | `formatVersion` 整数 + `migrations/migrate_<a>_to_<b>.gd` 逐级迁移 | 转换脚本数量爆炸 |

规格文档：
- [`docs/format/EE-FORMAT.md`](docs/format/EE-FORMAT.md) —— 项目格式（含扩展与前向兼容）
- [`docs/format/EE-IR.md`](docs/format/EE-IR.md) —— IR 规范（含让步语义契约、两条逃生舱）
- [`docs/format/SYNC.md`](docs/format/SYNC.md) —— 积木 ↔ 场景双向同步规则

工作清单与验收结果：[`docs/M1-TODO.md`](docs/M1-TODO.md)

> 顺带一提：注册表的交叉校验在第一次运行时就抓出一个真错误——`core.control.warp`
> 引用了不存在的 op。**在编译期暴露是一行提示，在运行期暴露就是一个线上崩溃。**

## 三个最关键的认知

1. **Gandi 的 GUI 编辑器不开源**，开源的是 VM / 积木渲染 / 扩展生态。自建编辑器是必然选择。
2. **难点不在积木，在调度器。** TurboWarp 的 `thread.js` + `execute.js` + `sequencer.js` 共 1425 行，解决了所有积木语言共同的难题：让步点、warp 原子模式、广播等待、克隆体生命周期。这部分参考其设计（MPL-2.0），是控制风险的关键。
3. **元积木是"永不缺积木"的保证。** 只做 6 个通用元积木（读写属性 / 调用方法 / 连接信号 / 发信号 / 新建节点 / 实例化场景）+ `ClassDB` 自动补全，就能覆盖 Godot 几乎全部 API，不必为每个 API 手工造积木。

## 进度

- [x] **M0** 环境、源码、Godot 构建链路（SCons + MSVC 14.44 已打通）、**界面 100% 汉化**
- [x] **M1** `.ee` 格式 / IR / 同步规则定稿，编译管线跑通，扩展机制实测可用
- [ ] M2 调度器（线程 / 让步 / warp / 广播 / 克隆体）+ 表达式求值器 + 节点桥
- [ ] M3 核心积木接到 Godot + 三条逃生舱 → 第一个可玩 Demo
- [ ] M4 fork scratch-gui 自研编辑器（L1 积木模式 / L2 场景模式）
- [ ] M4.5 L3 引擎模式（Godot 编辑器插件 + 清理遗留痕迹）
- [ ] M5 Windows 一键发布
- [ ] M6 Godot 能力积木库（物理 / 粒子 / 着色器 / 瓦片 / 动画 / 场景 / 存档 / 相机 / 联机）
- [ ] M7 `.sb3` 导入器、素材库、云存档、Android / Web
