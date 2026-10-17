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

## 三个最关键的认知

1. **Gandi 的 GUI 编辑器不开源**，开源的是 VM / 积木渲染 / 扩展生态。自建编辑器是必然选择。
2. **难点不在积木，在调度器。** TurboWarp 的 `thread.js` + `execute.js` + `sequencer.js` 共 1425 行，解决了所有积木语言共同的难题：让步点、warp 原子模式、广播等待、克隆体生命周期。这部分参考其设计（MPL-2.0），是控制风险的关键。
3. **元积木是"永不缺积木"的保证。** 只做 6 个通用元积木（读写属性 / 调用方法 / 连接信号 / 发信号 / 新建节点 / 实例化场景）+ `ClassDB` 自动补全，就能覆盖 Godot 几乎全部 API，不必为每个 API 手工造积木。

## 进度

- [x] **M0** 环境、源码、Godot 构建链路（SCons + MSVC 14.44 已打通）
- [ ] M1 数据模型与 `.ee` 项目格式、IR 设计
- [ ] M2 调度器（线程 / 让步 / warp / 广播 / 克隆体）+ 节点桥
- [ ] M3 核心积木接到 Godot → 第一个可玩 Demo
- [ ] M4 fork scratch-gui 自研编辑器
- [ ] M5 Windows 一键导出
- [ ] M6 Godot 能力积木库（物理 / 粒子 / 着色器 / 瓦片 / 动画 / 场景 / 存档 / 相机 / 联机）
- [ ] M7 `.sb3` 导入器、素材库、云存档、Android / Web
