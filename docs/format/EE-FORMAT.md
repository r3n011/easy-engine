# `.ee` 项目格式规范 v1

> 目标：一份**能活很久**的项目格式。判断标准不是"现在够不够用"，而是
> **三年后改 IR、加能力、升级 Godot 时，老项目还能不能打开**。

## 一、文件形态

`.ee` 就是一个 zip 包：

```
project.ee
├── project.json      ← 项目主数据（本规范描述的就是它）
├── assets/           造型 / 声音 / 字体 / 场景
│   ├── cat.png
│   └── jump.ogg
└── ir/               可选：编译缓存（见 §7）
    └── cache.json
```

单独一个 `project.json` 也是合法的（便于手写与做测试，如 `runtime/tests/sample.ee.json`）。

## 二、顶层结构

```jsonc
{
  "formatVersion": 1,              // ★ 格式版本，必须
  "name": "会跳的小猫",
  "generator": { "name": "Easy Engine Editor", "version": "0.1.0" },

  "godotApiVersion": "4.7.2",      // ★ 编写时所依据的 Godot API 版本
  "extensions": [                  // ★ 依赖的扩展与版本约束
    { "id": "ee.physics2d", "version": ">=1" }
  ],

  "stage": { "size": [480, 360], "background": "assets/bg.png", "settings": {} },
  "globals": { "variables": [...], "lists": [...] },
  "nodes": [ ... ],                // 角色 / 节点，见 §4

  "ext": {}                        // 未知字段保留区（见 §6）
}
```

### 为什么要 `godotApiVersion`

「Godot 通用」积木（元积木）会直接引用 Godot 的 API 名，例如
`调用 节点 的 "move_and_slide" 方法`。Godot 升级时 API 会被改名或移除。
记录编写时的版本后，运行时可以：

1. 找出项目里用到的、在新版已改名的 API；
2. 通过 `api_compat.gd` 的映射表自动替换；
3. 给出「这条积木需要 Godot 4.7 的 `x`，新版叫 `y`」这样的提示，而不是运行时崩。

**没有这个字段，Godot 每次大版本升级都会让一批项目静默损坏。**

## 三、积木脚本的表示法

这是我们自己定义的表示法。**不采用 Blockly 的序列化格式**，原因有三：

1. Blockly 的 JSON 里全是 block id / `inputs` / `fields` / `shadow` 等内部概念，
   **Blockly 一升级，我们的项目文件就可能读不出来**；
2. 它无法手写，也让 diff 变得没法看；
3. 我们要的是一份能**长期稳定**的格式。

编辑器把 Blockly 工作区当作**纯视图**：打开项目时把脚本渲染成 Blockly 积木，用户改完后
再序列化回本表示法。

### 3.1 积木对象

```jsonc
{
  "block": "core.motion.move_steps",     // ★ 积木 id（不是 opcode！见 §5）
  "inputs": {
    "STEPS": { "value": 10 }             // 值输入：字面量
  },
  "next": { ... }                        // 同一段里的下一个积木
}
```

值输入可以嵌一个积木（这就是"积木里塞积木"）：

```jsonc
"inputs": {
  "COND": {
    "value": {
      "block": "core.sensing.touching",
      "inputs": { "OTHER": { "value": "@mouse" } }
    }
  }
}
```

分支（语句块）输入用 `stack`，形状与 Blockly 一致（**链表，不是数组**）：

```jsonc
"branches": [ { "name": "BODY" } ]        // 在积木定义里声明

"inputs": {
  "BODY": {
    "stack": {
      "block": "core.motion.move_steps",
      "inputs": { "STEPS": { "value": 10 } },
      "next": {
        "block": "core.control.delete_clone"
      }
    }
  }
}
```

### 3.2 脚本

一个脚本 = 一个帽子积木 + 它的主体。

```jsonc
"scripts": [
  { "top": { "block": "core.event.when_flag_clicked", "inputs": { "BODY": { "stack": {...} } } } }
]
```

### 3.3 节点引用（`@` 记号）

| 写法 | 含义 |
|---|---|
| `"@self"` | 当前脚本所属的节点 |
| `"@stage"` | 舞台根节点 |
| `"@mouse"` | 鼠标（用于「碰到鼠标指针」） |
| `"@any_sprite"` | 任意角色（用于「碰到任意角色」） |
| `"Player"` | 按节点 id 指名引用 |

## 四、节点

```jsonc
{
  "id": "Player",                  // ★ 唯一，积木用它引用
  "name": "小猫",                   // 显示名（可重复）
  "template": "CHARACTER_BODY_2D", // ★ 节点模板，决定 Godot 节点类型
  "parent": "@stage",              // 父节点
  "order": 0,                      // 同级顺序 = 图层顺序
  "transform": { "position": [0, 0], "rotation": 0, "scale": [100, 100] },
  "visible": true,
  "costumes": [ { "id": "c1", "name": "默认", "asset": "assets/cat.png" } ],
  "sounds":   [ { "id": "s1", "name": "跳跃", "asset": "assets/jump.ogg" } ],
  "localVariables": [ { "id": "l_hp", "name": "生命", "value": 3 } ],
  "scripts": [ ... ]
}
```

**`template` 是这套设计的关键**：Scratcher 看到的是"角色"，底层是可替换的 Godot 节点模板。

| 模板 | Godot 节点 | 给谁用 |
|---|---|---|
| `SPRITE_2D` | `Node2D + Sprite2D` | 默认，纯贴图 |
| `CHARACTER_BODY_2D` | `CharacterBody2D + CollisionShape2D + Sprite2D` | 平台跳跃 |
| `RIGID_BODY_2D` | `RigidBody2D + ...` | 真实物理 |
| `AREA_2D` | `Area2D + CollisionShape2D` | 触发器（金币、检测区） |
| `CONTROL` | `Control` | UI |

> 模板表是**数据驱动**的（`runtime/ee/defs/templates.json`），扩展可以注册新模板。

## 五、★ 最重要的一条：`.ee` 里不出现 opcode

项目文件引用的是**积木 id**（`core.motion.move_steps`），不是 **opcode**（`motion.move_steps`）。
两者之间的映射写在积木定义里：

```jsonc
// blocks.core.json
{
  "id": "core.motion.move_steps",
  "ir": { "op": "motion.move_steps", "steps": { "$arg": "STEPS" } }
}
```

**这条决定带来的是"IR 可以自由演进"**：

| 场景 | 没有这条时 | 有这条时 |
|---|---|---|
| 把 `motion.step` 改名成 `motion.move` | 所有老项目的 opcode 都要批量改 | 改定义文件一行，老项目不动 |
| 把一个 op 拆成两个 | 老项目全坏 | 改定义里的 `ir` 模板 |
| 换一套全新的 IR | 灾难 | 同上 |

代价是每次打开项目要多做一次映射（成本可忽略，且有缓存）。

## 六、扩展性与前向兼容

### 6.1 扩展机制

```
runtime/ee/defs/
├── blocks.core.json              核心积木（ee.core）
├── ops.core.json                 核心 op
├── blocks.ee.physics2d.json      扩展 ee.physics2d 的积木
└── ops.ee.physics2d.json         扩展 ee.physics2d 的 op
```

**文件名前缀决定类别与归属**。新增能力 = 新增文件，**不需要改引擎代码**。

- 积木与 op 都带 `version`。要改行为就**加新 id**，不要原地改，否则老项目行为会变。
- 扩展用 `requires` 声明依赖与版本约束（支持 `>=1`、`<3`、`=2`）。
- 运行时若遇到未启用的扩展积木，报错会明确告诉你**该启用哪个扩展**，并指出位置。

### 6.2 未知字段保留（前向兼容）

**旧版工具打开新版项目、保存后不能把新字段抹掉。**

实现方式是：加载器**从不重建字典**，只在原始字典上读写。因此任何我们不认识的字段
（比如 `ext` 里的东西）会原样存活到保存。

任何对象都允许 `ext` 字段作为"扩展数据保留区"。约定：

- 扩展写入的数据放 `ext`，键名用扩展 id，例如 `"ext": { "ee.physics2d": {...} }`
- 核心不认识 `ext` 的内容，只负责原样搬运

### 6.3 版本约束语法

| 写法 | 含义 |
|---|---|
| `">=1"` | 至少 1（最常用，表示"我需要 1 的特性，2 也能用"） |
| `"=2"` | 精确 2 |
| `"<3"` | 小于 3 |
| `""` | 任意 |

## 七、版本迁移

`formatVersion` 是**整数**。改动 `.ee` 的结构时 +1，并在
`runtime/ee/migrations/` 补一个脚本：

```gdscript
# runtime/ee/migrations/migrate_1_to_2.gd
static func migrate(data: Dictionary) -> Dictionary:
    # 就地升级：把 stage.size 从 [w, h] 改成 { "w": w, "h": h }
    var s: Array = data.get("stage", {}).get("size", [480, 360])
    data["stage"]["size"] = { "w": s[0], "h": s[1] }
    return data
```

加载器会**逐级**跑迁移（1→2→3…），所以只需要写"每一步"，不用写 N² 个转换器。

### 向前兼容：文件比运行时新怎么办

不猜、不改，**只警告**，并按当前版本尽力加载。
因为未知字段会被保留，所以用旧版工具打开新项目、保存后也不会丢数据——
但用户会看到明确的提示。

## 八、IR 缓存

`.ee` 里可以带一份编译结果 `ir/cache.json`，用于跳过每次打开都要重新编译。

失效判据（**三者任一不同就重编译**）：

- `cache.irVersion` ≠ 运行时 `IR_VERSION`
- `cache.compilerVersion` ≠ 运行时 `COMPILER_VERSION`
- `cache.sourceHash` ≠ 项目脚本部分的哈希

缓存**永远可以被安全删掉**，它只是加速手段。

## 九、完整示例

见 `runtime/tests/sample.ee.json`（手写的、可编译的完整项目），
以及编译基准 `runtime/tests/sample.expected-ir.json`。

## 十、留给后续版本的扩展点

这些字段/v1 里**已经预留**，实现时可以逐步补上，不需要再改格式：

| 预留 | 用途 |
|---|---|
| `stage.settings` | 物理重力、渲染参数、输入映射 |
| `settings.export` | 导出配置（图标、包名、权限） |
| `ext` | 一切扩展数据 |
| `nodes[].localVariables[].value` | 克隆体继承的局部变量 |
| `ir/cache.json` | 编译缓存 |
| 扩展 `version` | 灰度升级：同一扩展可并存多个版本 |
