# Easy Engine IR 规范 v1

> IR（中间表示）是积木与引擎之间唯一的契约。
> **积木可以改、Godot 可以升级、调度器可以重写，但 IR 的形状要保持稳定**，
> 否则所有缓存和回归基准都得重做。

## 一、IR 长什么样

IR 是一棵**指令树**。语句是"有 `op` 的对象"，值可以是字面量，也可以是"有 `op` 的对象"。

```jsonc
// 语句：将 分数 增加 (1 + 1)
{
  "op": "var.change",
  "name": "分数",
  "delta": { "op": "op.expression", "source": "1 + 1" },
  "scope": "auto"
}

// 语句：重复 10 次 { 移动 10 步 }
{
  "op": "control.repeat",
  "times": 10,
  "body": [
    { "op": "motion.move_steps", "steps": 10, "target": "@self" }
  ]
}
```

判定规则很简单：

| 形状 | 含义 |
|---|---|
| `{ "op": "...", ... }` | 一个 op 节点 |
| 数字 / 字符串 / 布尔 / null | 字面量 |
| 数组 | op 序列（只有 `body` 这类分支字段用） |

## 二、值节点与语句节点

同一个对象形状，两种角色，靠 **op 定义里的 `pure`** 区分：

- `pure: true` → 可以放在值位置（表达式），求值不产生副作用
- `pure: false` → 只能放在语句位置

编译器不强制这一点（积木定义已经保证了正确用法），但**运行时求值器要靠它**决定
哪些节点可以在求值过程中直接算掉。

## 三、★ 让步语义（yields）：IR 与调度器的契约

每个 op 在定义里声明 `yields`：

```jsonc
{ "id": "control.wait",     "yields": true,  "pure": false, "args": ["seconds"] }
{ "id": "motion.move_steps","yields": false, "pure": false, "args": ["target", "steps"] }
{ "id": "op.add",           "yields": false, "pure": true,  "args": ["left", "right"] }
```

含义：

| 字段 | 含义 |
|---|---|
| `yields: true` | 这个 op **可能**挂起线程（`wait`、循环、`广播并等待`、`播放声音等待完成`） |
| `yields: false` | 一定不让步，可以连续执行 |
| `pure: true` | 无副作用，可在任意位置求值 |

**为什么放在定义里而不是硬编码在调度器里？**
因为扩展会引入新的会挂起的 op（比如"等待网络返回"）。
如果调度器硬编码一张表，扩展就永远做不了这类积木。

**M2 调度器的契约**：调度器只依赖 `yields` 这个字段，不依赖具体 op 名。
遇到 `yields: false` 的 op 就连续执行；遇到 `yields: true` 的就要准备好在任意点恢复。
`control.warp` 的作用是**在其 body 内临时把 `yields` 当作 false**（原子执行）。

## 四、目标引用（target）

积木默认作用于"当前角色"。这个"当前"在 IR 里是**显式**的，不靠隐式上下文：

```jsonc
{ "op": "motion.move_steps", "steps": 10, "target": "@self" }
{ "op": "looks.set_visible", "visible": true, "target": "Coin" }     // 指名另一个节点
{ "op": "looks.set_visible", "visible": true, "target": "@stage" }   // 舞台
```

可用取值见 `EE-FORMAT.md §3.3`。**运行时解析 target 得到节点实例的规则**：

```
"@self"   → 当前线程所属节点
"@stage"  → 舞台根
"@mouse"  → 鼠标（仅用于侦测）
"<节点id>" → 该 id 的节点实例；对克隆体而言是其"原型节点"
```

**克隆体怎么算？** 克隆体是原型节点的实例。`"@self"` 解析到具体克隆体，
而 `"Player"` 解析到原型。要"对所有克隆体做某事"，用专门的批量积木（M6），
而不是靠 target 语义去猜。

## 五、两条逃生舱在 IR 层的表现

这是 M1 里**必须预留**的东西，否则 M3 加不进去。

### 5.1 逃生舱①：表达式输入框

```jsonc
// 积木「表达式 [1 + 1]」编译成：
{ "op": "op.expression", "source": "1 + 1" }

// 它可以出现在任何值位置
{ "op": "var.set", "name": "分数", "value": { "op": "op.expression", "source": "hp * 2 + bonus" } }
```

`source` 是一段**受限表达式**（不是完整 GDScript）：数字、字符串、变量、
四则运算、比较、逻辑、括号、以及一组白名单函数（`sin`、`floor`、`clamp`…）。

好处是：**它是一等公民，可以参与优化、可以做类型推导、可以静态查错**，
而不是等运行到那一行才炸。M2 需要实现一个表达式求值器（约 300 行）。

### 5.2 逃生舱②：代码块

```jsonc
{
  "op": "code.gdscript",
  "source": "print(\"得分 = \", 分数)",
  "target": "@self"
}
```

与表达式不同，它是完整 GDScript，**共享积木的变量与节点**。
`yields: true`，因为它内部可能有 `await`。

它只在 L2/L3 出现，且在导出时可以被标记为"含代码"，让家长/老师一眼看到。

## 六、op 注册表与扩展

op 定义放在 `runtime/ee/defs/ops.<扩展id>.json`：

```jsonc
{
  "extension": "ee.physics2d",
  "extensionVersion": 1,
  "requires": [ { "id": "ee.core", "version": ">=1" } ],
  "ops": [
    {"id": "phy2d.apply_impulse", "yields": false, "pure": false, "args": ["target", "impulse"]}
  ]
}
```

**运行时只认 op，不认积木。** 所以：

- 扩展可以自由设计积木的外观（一个积木 → 多个 op，或多个积木 → 一个 op）
- 同一个 op 可以被多个积木复用
- 一个积木的 `ir` 模板里可以组合出任意 op 树（例如 `repeat_until` 展开成
  `control.while` + `op.not`）

### 参数默认值也放定义里

```jsonc
{"id": "var.set", "args": ["name", "value", "scope"], "defaults": {"scope": "auto"}}
```

积木没提供、也不是字面量的参数，由 `defaults` 补齐。
**这样默认值也是数据，扩展照做即可**，编译器里没有任何针对具体 op 的特例。

## 七、稳定性策略

| 变更 | 要不要动 IR 版本 | 做法 |
|---|---|---|
| 加一个新 op | 否 | 加定义文件即可，老 IR 不受影响 |
| 加一个新字段到已有 op | 否 | 老 IR 缺这个字段，运行时按缺省处理 |
| 改已有 op 的语义 | **是** | `IR_VERSION + 1`，并在迁移里处理 |
| 改编译器实现（不改语义） | 否 | `COMPILER_VERSION + 1` 让缓存失效即可 |
| 拆/合 op | **否** | 只改积木定义里的 `ir` 模板 —— 这正是 `.ee` 不存 opcode 的收益 |

`irVersion` / `compilerVersion` / `godotApiVersion` 会写进 IR 头部，
便于运行时、缓存与问题排查三方面判断兼容性。

## 八、IR 头部

```jsonc
{
  "irVersion": 1,
  "compilerVersion": 1,
  "sourceFormatVersion": 1,
  "godotApiVersion": "4.7.2",
  "name": "示例：会跳的小猫",
  "extensions": [ { "id": "ee.physics2d", "version": ">=1" } ],
  "stage": { ... },
  "globals": { "variables": [...], "lists": [...] },
  "nodes": [ { "id": "...", "template": "...", "scripts": [ <op> ] } ]
}
```

**`extensions` 是运行时的启动检查清单**：启动时逐一确认扩展可用，缺了就给出
「这个项目需要 ee.physics2d，请安装」的提示，而不是跑到一半崩掉。

## 九、完整的 IR 示例

见 `runtime/tests/sample.expected-ir.json`——它是回归基准，任何编译器改动都必须
保证要么输出不变，要么明确是有意变更并同步更新基准。
