# M3 工作清单与验收结果

> 目标：**把节点桥接到真实 Godot、落地三条逃生舱、做出第一个能玩的东西。**
>
> 契约：M2 定下的调度语义**一行都不许改**（见 `EE-SCHEDULER.md §13`）。
> 结果：`runtime.gd` / `thread.gd` / `values.gd` **确实一行没动**，只换了桥的实现。

## 一、交付物

| 文件 | 作用 |
|---|---|
| `runtime/ee/bridge/godot_bridge.gd` | **真实 Godot 节点桥**：建节点树、坐标换算、造型、特效、侦测、输入、元积木、执行代码 |
| `runtime/ee/bridge/code_env.gd` | 「执行代码」积木里 `env` 对象的实现 |
| `runtime/ee/shaders/sprite_effects.gdshader` | 图形特效：颜色/鱼眼/旋转/像素化/马赛克/亮度/虚像 |
| `runtime/player/player.gd` + `player.tscn` | 播放器：加载 `.ee`、搭舞台、每帧驱动运行时 |
| `runtime/tests/demo.ee.json` | **可玩 Demo：接苹果** |
| `runtime/tests/assets/*.png` | 演示素材（`tools/make-demo-assets.py` 生成，不依赖外部下载） |
| `runtime/brand/icon.png` | 启动画面与窗口图标 |
| `assets/brand/*` | 项目 logo（完整版 / 图标 / 文字，SVG + 多尺寸 PNG） |
| `tools/run-demo.ps1` | 启动游戏 → 截图 → 退出，并打印游戏的控制台输出 |

## 二、验收结果

```
$ powershell -File tools/run-demo.ps1 -WaitSec 10 -Diag -MoveMouse "500,600"
窗口已就绪，运行 10 秒 ...
已保存: docs/shot-demo.png

==== 播放器输出 ====
  [player] 项目已启动：res://tests/demo.ee.json
```

截图（`docs/shot-demo.png`）里可以看到：

- **舞台铺满窗口**：天空渐变、太阳、草地
- **苹果在落**，**篮子跟着鼠标在底部移动**
- **分数监控显示「分数 8」**（Scratch 式的变量监视器）
- **篮子变成了金色** —— 这是「执行代码」积木在跑
- **下落速度随分数变快** —— 这是表达式积木在跑

诊断输出（每 60 帧）：

```
  Basket  scratch=(149.5, -140.0) size=(80.0, 44.0) godot=(149.5, 140.0)  分数=1.0
  Apple   scratch=(-7.0, 59.0)    size=(40.0, 40.0) godot=(-7.0, -59.0)   分数=1.0
  Basket  scratch=(115.5, -140.0) ······                                  分数=1.0
  Apple   scratch=(-7.0, -121.0) ······                                   分数=1.0
  Basket  scratch=(-43.5, -140.0) ······                                  分数=2.0
```

位置、方向、包围盒、分数都对得上——**帧数与位移能对上，说明调度与渲染是同步的**。

## 三、坐标约定（只在这一层换算）

| | Scratch | Godot |
|---|---|---|
| 位置 | 中心原点、y 向上 | `Vector2(x, -y)`，舞台根在窗口中心 |
| 方向 | 0=上 90=右（逆时针） | `rotation = deg_to_rad(direction - 90)` |
| 大小 | 百分比 | `scale = percent / 100` |

**积木侧、编译器、调度器、op 实现全都只用 Scratch 坐标**，
只有 `godot_bridge.gd` 在写节点的那一刻换算一次。

舞台用"缩放根节点"而不是 SubViewport：SubViewportContainer 的 `stretch` 会自己改
SubViewport 的尺寸，多一层换算就多一处能错，居中布局也容易出问题。
现在窗口 = 480×360 × 2，舞台根 `scale = 2`、位置在窗口中心，效果等价且好懂。
放大用最近邻采样，像素画不糊。

## 四、三条逃生舱的落地情况

| 逃生舱 | 状态 | 说明 |
|---|---|---|
| **① 表达式输入框** | ✅ | `op.expression` + `ee/expr.gd` 的受限表达式求值；Demo 里用它让下落速度随分数增长：`-(3 + 分数 * 0.2)`。编译一次求值多次，循环里不重复解析 |
| **② 代码块** | ✅ | `godot_bridge._execute_code` 动态编译并执行 GDScript，**与积木共享变量与节点**：用户直接写 `分数 = 分数 + 1`、`node.modulate = Color(...)`。桥会扫描代码里出现的变量名生成局部变量、跑完写回。按源码缓存编译结果，循环里每帧执行也不会重编译 |
| **③ 可视化替代** | ⏳ M6 | 着色器/噪声/动画树做成"选预设+调参数"的面板 |

## 五、这一轮修掉的三个真 bug

这三个都只有"真的接上 Godot 并且真的玩起来"才会暴露：

**1. 共享的 op 上下文被嵌套求值覆盖**

`_ctx` 是复用的单例。求值嵌套表达式时会递归进入 `_dispatch`，把 `_ctx.op` 改成内层的 op，
于是外层「移到 x: 鼠标x y: -140」里的 `y` 读到了错的对象 → y 恒为 0。

现象：所有角色都堆在中间，分数每帧都涨。
修法：`_dispatch` 保存/恢复上下文。

**2. 着色器把 Godot 的 `modulate` 盖掉了**

`fragment()` 里直接 `COLOR = col`，把引擎传进来的 `modulate` 丢了，
所以「执行代码」里改 `node.modulate` 看不见效果。
修法：`COLOR = col * modulate`。

**3. 表达式求值把线程当成了目标**

`op_op_expression` 传的是 `ctx.thread` 而不是 `ctx.target`，
求值变量时去读 `thread.vars` → 崩。

**共同点**：M2 的 84 项测试全都盖不住它们，因为它们都发生在"桥/集成"这一层。
这说明 M2 与 M3 的边界划对了——语义在 M2 测清，集成问题在 M3 暴露。

## 六、素材为什么是自己画的

`tools/make-demo-assets.py` 用纯 Python 写 PNG（不引第三方库）生成苹果、篮子、背景。
理由：演示要能一键复现，就不能依赖外部素材下载。
（M7 的素材库会是另一回事。）

## 七、M3 的边界（明确没做的）

| 没做 | 原因 / 什么时候做 |
|---|---|
| **积木可视化编辑器** | **M4**。现在积木是手写 JSON，不是拖出来的——这是最该补的一环 |
| 「代码 → 积木」转换器 | 已列入 M3.5（用户明确要求） |
| 自制积木（有参数、有返回值） | 转换器需要它来转换带函数的代码，一并放 M3.5 |
| 像素级碰撞 | 有意不做（方案 D4）：AABB 观感更好、性能更高 |
| 声音播放的真实时长 | 桥已实现播放；Demo 没放音频素材 |
| 多场景 / 存档 / 导出 | M5 / M6 |
| 300 个克隆体以外的性能优化 | 等有真实负载再说 |

## 八、下一步

1. **M3.5**：代码 ↔ 积木互通（GDScript → 积木脚本；积木 → GDScript）+ 自制积木
2. **M4**：fork `scratch-gui` 做真正的积木编辑器，让"用积木做游戏"变成拖出来的事
