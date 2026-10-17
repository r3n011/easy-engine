# M1 工作清单

> 目标：**定稿数据模型与 IR**，并跑通「手写 `.ee` → 编译出 IR」。
> 硬约束：**扩展性**与**后期更新**必须由格式本身保证，不能靠"以后再说"。

## 一、必须解决的四个"将来会痛"的问题

| 问题 | 如果 M1 不做会怎样 | M1 的对策 |
|---|---|---|
| **IR 变了，老项目打不开** | 每次改 IR 都要写一遍转换脚本，越写越乱 | `.ee` **只引用积木 id，不引用 opcode**；opcode 由积木定义映射出来 |
| **加一个新积木要改引擎代码** | 社区无法扩展，我们自己也慢 | 积木与 op 全部**数据驱动**（JSON），新增 = 加文件 |
| **新版格式被旧版工具打开后丢数据** | 用户用旧版打开新项目，保存后新字段全没了 | **未知字段原样保留**（forward compatibility） |
| **Godot 升级把项目搞坏** | 元积木引用的 API 改名就报错 | 记录 `godotApiVersion` + **API 改名映射表** |

## 二、交付物

### 文档（规格定稿）
- `docs/format/EE-FORMAT.md` —— `.ee` 项目格式（版本、扩展、迁移）
- `docs/format/EE-IR.md` —— IR 规范（节点、让步语义、表达式、目标引用）
- `docs/format/SYNC.md` —— 积木 ↔ 场景双向同步规则

### 代码（可运行的编译管线）
```
runtime/                              Godot 项目（运行时）
  project.godot
  ee/
    version.gd                        版本常量与兼容判断
    registry.gd                       积木/op 注册表（数据驱动 + 可扩展）
    project.gd                        .ee 加载、校验、未知字段保留
    compiler.gd                       积木脚本 → IR
    defs/
      blocks.core.json                ★ 核心积木定义（编辑器与运行时共用）
      ops.core.json                   ★ 核心 op 定义（让步/纯函数语义）
      blocks.ee.physics2d.json        扩展示例：物理积木
      ops.ee.physics2d.json
  tools/
    cli.gd                            验收用：编译 .ee 并输出 IR / 校验
  tests/
    sample.ee.json                    手写的示例项目
    sample.expected-ir.json           期望的 IR 输出（回归基准）
```

### 验收
```powershell
# 1) 编译手写的 .ee，输出 IR
godot --headless --path runtime --script tools/cli.gd -- compile tests/sample.ee.json

# 2) 校验（不产出 IR，只报问题）
godot --headless --path runtime --script tools/cli.gd -- check  tests/sample.ee.json

# 3) 扩展性证明：加载扩展定义后，扩展积木也能编译
godot --headless --path runtime --script tools/cli.gd -- compile tests/sample.ee.json --ext ee.physics2d

# 4) 回归：与期望 IR 逐字节比对
godot --headless --path runtime --script tools/cli.gd -- regress
```

## 三、扩展性设计要点（写死进格式）

1. **两级注册表**：`blocks.*.json`（编辑器可见）与 `ops.*.json`（运行时语义），文件名前缀决定加载。
   `blocks.ee.physics2d.json` 里的积木属于扩展 `ee.physics2d`。
2. **id 带命名空间**：`core.motion.move_steps` / `ee.physics2d.apply_impulse`。
3. **每个定义带 `version`**：扩展升级时只加不改；要改就加新 id。
4. **op 未知时明确报错**，附带"你需要哪个扩展"的提示，而不是静默失败。
5. **`ext` 保留区**：任何对象都允许 `ext` 字段，加载器原样保存。
6. **迁移链**：`formatVersion` 升级走 `migrations/` 目录里按序号排列的脚本。

## 四、进度

- [x] `.ee` 格式规范 → `docs/format/EE-FORMAT.md`
- [x] IR 规范 → `docs/format/EE-IR.md`
- [x] 积木 ↔ 场景同步规则 → `docs/format/SYNC.md`
- [x] 版本与迁移机制 → `runtime/ee/version.gd` + `runtime/ee/migrations/`
- [x] 注册表（数据驱动、可扩展）→ `runtime/ee/registry.gd`
- [x] 编译器 → `runtime/ee/compiler.gd`
- [x] `.ee` 加载与校验 → `runtime/ee/project.gd`
- [x] CLI 与回归基准 → `runtime/tools/cli.gd`
- [x] 扩展性演示 → `ee.physics2d`（7 个积木 / 8 个 op，只加文件、没改引擎）

## 五、验收结果

```
$ powershell -File tools/test-runtime.ps1

==== 1. 定义注册表 ====
  扩展 2 个，积木 95 个，op 95 个，分类 12 个；错误 0，警告 0
  ee.core       v1  积木 88 个，op 87 个
  ee.physics2d  v1  积木  7 个，op  8 个
  （无问题）

==== 2. 示例项目校验 ====
  （无问题）
  -- 编译检查 --（无问题）  节点 2 个，脚本 3 个

==== 3. IR 回归 ====
  回归通过：IR 与基准一致（5090 字节）

M1 全部验收通过。
```

### 扩展性实测

```powershell
# 只启用核心，物理积木会被拒绝，并给出可执行的提示
$ godot --headless --path runtime --script tools/cli.gd -- compile tests/sample.ee.json --ext ee.core
== 编译失败 ==
  [错误] block_ext_disabled  积木 ee.physics2d.apply_impulse 来自扩展 ee.physics2d，
                             当前未启用。请用 --ext ee.physics2d 启用。
        @ 节点 Player 的脚本 #0
  [错误] block_ext_disabled  积木 ee.physics2d.is_on_floor 来自扩展 ee.physics2d，
                             当前未启用。请用 --ext ee.physics2d 启用。
        @ 节点 Player 的脚本 #1 / 输入 COND
```

注意报错带**位置**（哪个节点的第几个脚本、哪个输入），这是后面做编辑器时能跳转到
出错积木的基础。

### 顺带抓到的真问题

注册表的交叉校验在第一次运行时就抓出一个错误：积木 `core.control.warp` 引用了
不存在的 op `control.warp_begin`（我在改名时漏改了积木模板）。
**这类错误如果在运行时才暴露，就是一个线上崩溃；在编译期暴露就是一行提示。**

## 六、下一步（M2）需要接上的契约

M2 写调度器时，只依赖 IR 规范里的两件事：

1. **`yields` 字段**（来自 op 定义，不是硬编码的表）——决定哪里可以挂起线程
2. **`body` 是 op 数组，`target` 是显式引用**——不需要猜上下文

另外 M2 必须实现**表达式求值器**（逃生舱① 的落地），因为 IR 里已经有
`op.expression` 节点了。
