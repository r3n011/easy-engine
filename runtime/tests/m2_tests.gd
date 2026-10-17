# M2 测试：调度器的让步语义、warp、广播、克隆体，以及值语义与表达式。
#
# 运行:
#   godot --headless --path runtime --script tests/m2_tests.gd
#
# 这些用例是"积木语言能不能用"的底线。改调度器时它们必须全绿。
extends SceneTree

const Registry = preload("res://ee/registry.gd")
const Runtime = preload("res://ee/runtime.gd")
const NodeBridge = preload("res://ee/bridge/node_bridge.gd")
const Values = preload("res://ee/values.gd")
const Expr = preload("res://ee/expr.gd")

var passed := 0
var failed := 0
var _current := ""

# ---------------------------------------------------------------- 小框架

func group(name: String) -> void:
	print("\n== %s ==" % name)


func check(case: String, cond: bool, detail := "") -> void:
	if cond:
		passed += 1
		print("  OK   " + case)
	else:
		failed += 1
		print("  FAIL " + case + ("   " + detail if detail != "" else ""))


func check_eq(case: String, got: Variant, want: Variant) -> void:
	check(case, _same(got, want), "实际 %s，期望 %s" % [_fmt(got), _fmt(want)])


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		return is_equal_approx(a, b)
	return a == b


func _fmt(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		return Values.number_to_string(v)
	return str(v)


# ---------------------------------------------------------------- IR 构造辅助

func hat(kind: String, body: Array, params := {}) -> Dictionary:
	return { "op": "event.hat", "kind": kind, "params": params, "body": body }


func op(oid: String, args := {}) -> Dictionary:
	var d := { "op": oid }
	for k in args:
		d[k] = args[k]
	return d


func node(id: String, scripts: Array, extra := {}) -> Dictionary:
	var n := {
		"id": id, "name": id, "template": "SPRITE_2D", "parent": "@stage",
		"order": 0, "transform": { "position": [0, 0], "rotation": 0, "scale": [100, 100] },
		"visible": true, "costumes": [], "sounds": [], "localVariables": [],
		"scripts": scripts,
	}
	for k in extra:
		n[k] = extra[k]
	return n


func make_ir(nodes: Array, global_vars: Array = [], global_lists: Array = [], ext := "ee.core") -> Dictionary:
	return {
		"irVersion": 1, "compilerVersion": 1, "sourceFormatVersion": 1,
		"godotApiVersion": "4.7.2", "name": "test",
		"extensions": [{ "id": ext, "version": ">=1" }],
		"stage": { "size": [480, 360] },
		"globals": { "variables": global_vars, "lists": global_lists },
		"nodes": nodes,
	}


# 搭一个只启用核心（或加上扩展）的运行时
func build(ir: Dictionary, enabled: Array = []):
	var reg = Registry.new()
	reg.load_defs("res://ee/defs", enabled)
	var bridge = NodeBridge.new()
	var rt = Runtime.new()
	rt.setup(reg, bridge)
	rt.load_ir(ir)
	_runtimes.append(rt)
	return { "rt": rt, "bridge": bridge, "reg": reg }

var _runtimes: Array = []


# 释放所有运行时，打断 Thread <-> Target 的引用环（否则 ObjectDB 会报泄漏）
func dispose_all() -> void:
	for rt in _runtimes:
		rt.dispose()
	_runtimes.clear()


func var_of(rt, name: String) -> Variant:
	return rt.get_var(name, "global", null)


# ---------------------------------------------------------------- 入口

func _init() -> void:
	seed(12345)

	print("=== Easy Engine M2 测试 ===")

	_check_providers()
	_check_values()
	_check_expression()
	_check_sequence()
	_check_loop_yield()
	_check_warp()
	_check_wait()
	_check_wait_until()
	_check_forever()
	_check_broadcast()
	_check_broadcast_wait()
	_check_clone()
	_check_scope()
	_check_list()
	_check_motion()
	_check_bounce()
	_check_stop()
	_check_extension()
	_check_unknown_op()

	dispose_all()
	print("\n通过 %d，失败 %d" % [passed, failed])
	quit(0 if failed == 0 else 1)


# ---------------------------------------------------------------- 用例

func _check_providers() -> void:
	group("provider 完整性")
	for exts in [[], ["ee.core"], ["ee.physics2d"]]:
		var reg = Registry.new()
		reg.load_defs("res://ee/defs", exts)
		var rt = Runtime.new()
		rt.setup(reg, NodeBridge.new())
		check_eq("启动校验无错误 (ext=%s)" % str(exts), rt.errors.size(), 0)
		if rt.errors.size() > 0:
			print("      DETAIL: " + str(rt.errors))
		rt.dispose()


func _check_values() -> void:
	group("值语义")
	# "10" > "9" 走数字比较（比 JavaScript 的字典序直觉更好预测）
	check("\"10\" > \"9\" 为真（数字比较）", Values.compare("10", "9") == 1)
	check_eq("10 与 \"10\" 相等", Values.equals(10, "10"), true)
	check_eq("空串与 0 相等", Values.equals("", 0), true)
	check_eq("加法：两边都是数字", Values.add("3", 4), 7.0)
	check_eq("加法：有非数字则拼接", Values.add("abc", 4), "abc4")
	check_eq("布尔加法", Values.add(true, 1), 2.0)
	check_eq("整数值不带 .0", Values.to_string_value(10.0), "10")
	check_eq("小数保留", Values.to_string_value(10.25), "10.25")
	check_eq("除零得 Infinity", Values.to_string_value(Values.div(1, 0)), "Infinity")
	check_eq("0/0 得 NaN", Values.to_string_value(Values.div(0, 0)), "NaN")
	check_eq("四舍五入 0.5 远离零", Values.round_to_nearest(10.5), 11.0)
	check_eq("四舍五入 -0.5 远离零", Values.round_to_nearest(-0.5), -1.0)
	check_eq("非空字符串为真（含 \"false\"）", Values.to_bool("false"), true)


func _check_expression() -> void:
	group("逃生舱①：表达式")
	var cases := [
		["1 + 2 * 3", 7.0],
		["(1 + 2) * 3", 9.0],
		["2 ^ 3 ^ 2", 512.0],
		["10 % 3", 1.0],
		["-5 + 2", -3.0],
		["3 > 2 and 1 < 2", true],
		["not false", true],
		["min(3, 7)", 3.0],
		["clamp(15, 0, 10)", 10.0],
		["len(\"abcd\")", 4.0],
		["\"a\" == \"a\"", true],
	]
	for c in cases:
		var r := Expr.compile(c[0])
		if not r["ok"]:
			check("表达式可编译: " + c[0], false, r["error"])
			continue
		var v = Expr.evaluate(r["ast"], func(_n): return 0)
		check_eq("表达式 " + c[0], v, c[1])

	# 错误表达式要报错而不是崩
	var bad := Expr.compile("1 + * 2")
	check("错误表达式被拒绝", not bad["ok"], str(bad["error"]))
	check("错误带位置信息", int(bad["pos"]) > 0, "pos=%d" % int(bad["pos"]))

	# 变量查找走 lookup
	var r2 := Expr.compile("hp * 2 + bonus")
	var v2 = Expr.evaluate(r2["ast"], func(n): return { "hp": 10.0, "bonus": 5.0 }.get(n, 0))
	check_eq("表达式可读变量", v2, 25.0)


func _check_sequence() -> void:
	group("顺序执行")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("var.set", { "name": "甲", "value": 1.0, "scope": "auto" }),
			op("var.set", { "name": "乙", "value": 2.0, "scope": "auto" }),
			op("var.set", { "name": "丙", "value": 3.0, "scope": "auto" }),
		])]),
	], [{ "id": "g1", "name": "甲", "value": 0 }, { "id": "g2", "name": "乙", "value": 0 },
		{ "id": "g3", "name": "丙", "value": 0 }])
	var s = build(ir)
	check_eq("启动前无错误", s["rt"].errors.size(), 0)
	s["rt"].green_flag()
	s["rt"].step(0.1)
	check_eq("一次 step 跑完顺序脚本", var_of(s["rt"], "丙"), 3.0)
	check_eq("线程已结束", s["rt"].live_thread_count(), 0)


func _check_loop_yield() -> void:
	group("循环让步（Scratcher 的直觉：重复 3 次花 3 帧）")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("control.repeat", { "times": 3.0, "body": [
				op("var.change", { "name": "计数", "delta": 1.0, "scope": "auto" }),
			] }),
		])]),
	], [{ "id": "g1", "name": "计数", "value": 0 }])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].step(0.1)
	check_eq("第 1 帧后计数 = 1", var_of(s["rt"], "计数"), 1.0)
	s["rt"].step(0.1)
	check_eq("第 2 帧后计数 = 2", var_of(s["rt"], "计数"), 2.0)
	s["rt"].step(0.1)
	check_eq("第 3 帧后计数 = 3", var_of(s["rt"], "计数"), 3.0)
	check_eq("线程已结束", s["rt"].live_thread_count(), 0)
	s["rt"].step(0.1)
	check_eq("结束后不再增加", var_of(s["rt"], "计数"), 3.0)


func _check_warp() -> void:
	group("warp：不刷新屏幕（循环不让步）")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("control.warp", { "body": [
				op("control.repeat", { "times": 100.0, "body": [
					op("var.change", { "name": "计数", "delta": 1.0, "scope": "auto" }),
				] }),
			] }),
		])]),
	], [{ "id": "g1", "name": "计数", "value": 0 }])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].step(0.1)
	check_eq("warp 内 100 次循环一帧跑完", var_of(s["rt"], "计数"), 100.0)
	check_eq("线程已结束", s["rt"].live_thread_count(), 0)


func _check_wait() -> void:
	group("等待（按时间让步）")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("var.set", { "name": "阶段", "value": "开始", "scope": "auto" }),
			op("control.wait", { "seconds": 0.5 }),
			op("var.set", { "name": "阶段", "value": "结束", "scope": "auto" }),
		])]),
	], [{ "id": "g1", "name": "阶段", "value": "" }])
	var s = build(ir)
	s["rt"].green_flag()
	# 时间线：第 1 帧跑到 wait（此刻 now=0.1，到期时刻 0.6）
	s["rt"].step(0.1)
	check_eq("等待中", var_of(s["rt"], "阶段"), "开始")
	s["rt"].step(0.1)
	s["rt"].step(0.1)
	s["rt"].step(0.1)
	check_eq("0.4 秒时仍在等待", var_of(s["rt"], "阶段"), "开始")
	s["rt"].step(0.1)
	check_eq("0.5 秒时仍在等待（到期时刻 0.6）", var_of(s["rt"], "阶段"), "开始")
	s["rt"].step(0.1)
	check_eq("0.6 秒后继续", var_of(s["rt"], "阶段"), "结束")

	# 等待 0 秒仍然让出一帧
	var ir2 = make_ir([
		node("A", [hat("flag", [
			op("var.set", { "name": "阶段", "value": "A", "scope": "auto" }),
			op("control.wait", { "seconds": 0.0 }),
			op("var.set", { "name": "阶段", "value": "B", "scope": "auto" }),
		])]),
	], [{ "id": "g1", "name": "阶段", "value": "" }])
	var s2 = build(ir2)
	s2["rt"].green_flag()
	s2["rt"].step(0.1)
	check_eq("等待 0 秒也让步一帧", var_of(s2["rt"], "阶段"), "A")
	s2["rt"].step(0.1)
	check_eq("下一帧继续", var_of(s2["rt"], "阶段"), "B")


func _check_wait_until() -> void:
	group("等待直到（按条件让步）")
	var cond := op("op.gt", { "left": op("var.get", { "name": "计时", "scope": "auto" }), "right": 2.0 })
	var ir = make_ir([
		node("A", [hat("flag", [
			op("control.wait_until", { "cond": cond }),
			op("var.set", { "name": "结果", "value": "过了", "scope": "auto" }),
		])]),
	], [{ "id": "g1", "name": "计时", "value": 0 }, { "id": "g2", "name": "结果", "value": "" }])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].step(0.1)
	check_eq("条件不成立时等待", var_of(s["rt"], "结果"), "")
	s["rt"].set_var("计时", 5.0, "global", null)
	s["rt"].step(0.1)
	check_eq("条件成立后继续", var_of(s["rt"], "结果"), "过了")


func _check_forever() -> void:
	group("重复执行（每帧一轮）")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("control.forever", { "body": [
				op("var.change", { "name": "帧计数", "delta": 1.0, "scope": "auto" }),
			] }),
		])]),
	], [{ "id": "g1", "name": "帧计数", "value": 0 }])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].run_frames(5, 0.1)
	check_eq("5 帧各跑一轮", var_of(s["rt"], "帧计数"), 5.0)
	check("线程仍在运行", s["rt"].live_thread_count() == 1)
	s["rt"].stop_all()
	check_eq("停止后线程清空", s["rt"].live_thread_count(), 0)


func _check_broadcast() -> void:
	group("广播（不等待）")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("event.broadcast", { "message": "出发" }),
			op("var.set", { "name": "顺序", "value": "A先完成", "scope": "auto" }),
		])]),
		node("B", [hat("broadcast", [
			op("var.set", { "name": "顺序", "value": "B覆盖了", "scope": "auto" }),
		], { "message": "出发" })]),
	], [{ "id": "g1", "name": "顺序", "value": "" }])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].step(0.1)
	check_eq("A 先完成（B 在下一帧才跑）", var_of(s["rt"], "顺序"), "A先完成")
	s["rt"].step(0.1)
	check_eq("B 在下一帧覆盖", var_of(s["rt"], "顺序"), "B覆盖了")


func _check_broadcast_wait() -> void:
	group("广播并等待")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("var.set", { "name": "A状态", "value": "等B", "scope": "auto" }),
			op("event.broadcast_wait", { "message": "干活" }),
			op("var.set", { "name": "A状态", "value": "B已完成", "scope": "auto" }),
		])]),
		node("B", [hat("broadcast", [
			op("control.wait", { "seconds": 0.3 }),
			op("var.set", { "name": "B状态", "value": "做完", "scope": "auto" }),
		], { "message": "干活" })]),
	], [{ "id": "g1", "name": "A状态", "value": "" }, { "id": "g2", "name": "B状态", "value": "" }])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].run_frames(3, 0.1)
	check_eq("B 还在干活", var_of(s["rt"], "B状态"), "")
	check_eq("A 仍在等待", var_of(s["rt"], "A状态"), "等B")
	s["rt"].run_frames(4, 0.1)
	check_eq("B 完成", var_of(s["rt"], "B状态"), "做完")
	check_eq("A 等到 B 完成后才继续", var_of(s["rt"], "A状态"), "B已完成")


func _check_clone() -> void:
	group("克隆体（局部变量是副本）")
	var ir = make_ir([
		node("A", [
			hat("flag", [
				op("control.repeat", { "times": 3.0, "body": [
					op("control.clone_create", { "target": "@self" }),
				] }),
			]),
			hat("clone_start", [
				op("var.change", { "name": "生命", "delta": -1.0, "scope": "local" }),
			]),
		], { "localVariables": [{ "id": "l1", "name": "生命", "value": 3 }] }),
	])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].run_frames(6, 0.1)
	var clones := 0
	for t in s["rt"].targets:
		if t.is_clone:
			clones += 1
	check_eq("创建了 3 个克隆体", clones, 3)
	var proto = s["rt"].targets_by_id["A"]
	check_eq("原型的局部变量不变", proto.vars["生命"], 3.0)
	var clone = null
	for t in s["rt"].targets:
		if t.is_clone:
			clone = t
			break
	check_eq("克隆体的局部变量被改成 2", clone.vars["生命"], 2.0)

	# 上限
	s["rt"].max_clones = 2
	var s2 = build(ir)
	s2["rt"].max_clones = 2
	s2["rt"].green_flag()
	s2["rt"].run_frames(6, 0.1)
	var n2 := 0
	for t in s2["rt"].targets:
		if t.is_clone:
			n2 += 1
	check_eq("克隆体数量受上限限制", n2, 2)
	check("超限时有告警", s2["rt"].warnings.size() > 0, str(s2["rt"].warnings))


func _check_scope() -> void:
	group("变量作用域（局部遮蔽全局）")
	var ir = make_ir([
		node("A", [
			hat("flag", [
				op("var.set", { "name": "分数", "value": 100.0, "scope": "auto" }),
				op("var.set", { "name": "次数", "value": 5.0, "scope": "auto" }),
			]),
		], { "localVariables": [{ "id": "l1", "name": "分数", "value": 0 }] }),
	], [{ "id": "g1", "name": "分数", "value": 7 }, { "id": "g2", "name": "次数", "value": 0 }])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].step(0.1)
	var a = s["rt"].targets_by_id["A"]
	check_eq("同名局部变量被写", a.vars["分数"], 100.0)
	check_eq("全局的同名变量没被碰", var_of(s["rt"], "分数"), 7.0)
	check_eq("只有全局的才写全局", var_of(s["rt"], "次数"), 5.0)


func _check_list() -> void:
	group("列表")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("list.add", { "name": "物品", "value": "苹果", "scope": "auto" }),
			op("list.add", { "name": "物品", "value": "香蕉", "scope": "auto" }),
			op("list.insert", { "name": "物品", "index": 1.0, "value": "开头", "scope": "auto" }),
			op("list.replace", { "name": "物品", "index": 2.0, "value": "换了", "scope": "auto" }),
			op("list.delete", { "name": "物品", "index": 3.0, "scope": "auto" }),
			op("var.set", { "name": "个数", "value": op("list.length", { "name": "物品", "scope": "auto" }), "scope": "auto" }),
			op("var.set", { "name": "第一", "value": op("list.get", { "name": "物品", "index": 1.0, "scope": "auto" }), "scope": "auto" }),
			op("var.set", { "name": "找到", "value": op("list.index_of", { "name": "物品", "value": "换了", "scope": "auto" }), "scope": "auto" }),
			op("var.set", { "name": "含有", "value": op("list.contains", { "name": "物品", "value": "香蕉", "scope": "auto" }), "scope": "auto" }),
		])]),
	], [{ "id": "g1", "name": "个数", "value": 0 }, { "id": "g2", "name": "第一", "value": "" },
		{ "id": "g3", "name": "找到", "value": 0 }, { "id": "g4", "name": "含有", "value": false }],
		[{ "id": "gl1", "name": "物品", "value": [] }])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].run_frames(2, 0.1)
	check_eq("列表长度", var_of(s["rt"], "个数"), 2.0)
	check_eq("第一项", var_of(s["rt"], "第一"), "开头")
	check_eq("找到位置", var_of(s["rt"], "找到"), 2.0)
	check_eq("包含查询", var_of(s["rt"], "含有"), false)


func _check_motion() -> void:
	group("运动（方向 0=上 90=右）")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("motion.point_direction", { "direction": 90.0, "target": "@self" }),
			op("motion.move_steps", { "steps": 10.0, "target": "@self" }),
			op("motion.point_direction", { "direction": 0.0, "target": "@self" }),
			op("motion.move_steps", { "steps": 10.0, "target": "@self" }),
			op("var.set", { "name": "X", "value": op("motion.get_x", { "target": "@self" }), "scope": "auto" }),
			op("var.set", { "name": "Y", "value": op("motion.get_y", { "target": "@self" }), "scope": "auto" }),
		])]),
	], [{ "id": "g1", "name": "X", "value": 0 }, { "id": "g2", "name": "Y", "value": 0 }])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].step(0.1)
	check_eq("朝右走 10 步 → x = 10", var_of(s["rt"], "X"), 10.0)
	check_eq("朝上走 10 步 → y = -10（屏幕坐标 y 向下）", var_of(s["rt"], "Y"), -10.0)

	# 旋转
	var ir2 = make_ir([
		node("A", [hat("flag", [
			op("motion.turn", { "delta": 30.0, "mode": "cw", "target": "@self" }),
			op("var.set", { "name": "方向", "value": op("motion.get_direction", { "target": "@self" }), "scope": "auto" }),
		])]),
	], [{ "id": "g1", "name": "方向", "value": 0 }])
	var s2 = build(ir2)
	s2["rt"].green_flag()
	s2["rt"].step(0.1)
	check_eq("顺时针 30 度：90 → 120", var_of(s2["rt"], "方向"), 120.0)


func _check_bounce() -> void:
	group("碰到边缘就反弹")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("motion.set_position", { "x": 239.0, "y": 0.0, "target": "@self" }),
			op("motion.point_direction", { "direction": 90.0, "target": "@self" }),
			op("motion.bounce", { "target": "@self" }),
			op("var.set", { "name": "方向", "value": op("motion.get_direction", { "target": "@self" }), "scope": "auto" }),
			op("var.set", { "name": "X", "value": op("motion.get_x", { "target": "@self" }), "scope": "auto" }),
		])]),
	], [{ "id": "g1", "name": "方向", "value": 0 }, { "id": "g2", "name": "X", "value": 0 }])
	var s = build(ir)
	# 给个 32x32 的包围盒
	s["rt"].targets_by_id["A"].state["size"] = Vector2(32, 32)
	s["rt"].green_flag()
	s["rt"].step(0.1)
	check_eq("右边缘反射：90 → 90-180 = -90，等价 270", fmod(var_of(s["rt"], "方向") + 360.0, 360.0), 270.0)
	check("位置被推回边界内", float(var_of(s["rt"], "X")) <= 240.0)


func _check_stop() -> void:
	group("停止")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("control.forever", { "body": [
				op("var.change", { "name": "计数", "delta": 1.0, "scope": "auto" }),
			] }),
		])]),
		node("B", [hat("flag", [
			op("control.wait", { "seconds": 0.2 }),
			op("control.stop_all"),
		])]),
	], [{ "id": "g1", "name": "计数", "value": 0 }])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].run_frames(5, 0.1)
	check_eq("停止全部后清空线程", s["rt"].live_thread_count(), 0)
	var n = var_of(s["rt"], "计数")
	s["rt"].run_frames(5, 0.1)
	check_eq("停止后不再执行", var_of(s["rt"], "计数"), n)

	# 停止当前脚本
	var ir2 = make_ir([
		node("A", [hat("flag", [
			op("var.set", { "name": "阶段", "value": "前", "scope": "auto" }),
			op("control.stop", { "mode": "this" }),
			op("var.set", { "name": "阶段", "value": "后", "scope": "auto" }),
		])]),
	], [{ "id": "g1", "name": "阶段", "value": "" }])
	var s2 = build(ir2)
	s2["rt"].green_flag()
	s2["rt"].step(0.1)
	check_eq("停止当前脚本：后面的不执行", var_of(s2["rt"], "阶段"), "前")


func _check_extension() -> void:
	group("扩展 op 可用（证明扩展机制成立）")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("phy2d.set_velocity", { "velocity": op("vec2", { "x": 3.0, "y": -4.0 }), "target": "@self" }),
			op("var.set", { "name": "VX", "value": op("phy2d.get_velocity_x", { "target": "@self" }), "scope": "auto" }),
			op("var.set", { "name": "VY", "value": op("phy2d.get_velocity_y", { "target": "@self" }), "scope": "auto" }),
		])]),
	], [{ "id": "g1", "name": "VX", "value": 0 }, { "id": "g2", "name": "VY", "value": 0 }])
	var s = build(ir, [])   # 不限制扩展 = 全部启用
	check_eq("启动无错误", s["rt"].errors.size(), 0)
	s["rt"].green_flag()
	s["rt"].step(0.1)
	check_eq("扩展 op 执行成功 VX", var_of(s["rt"], "VX"), 3.0)
	check_eq("扩展 op 执行成功 VY", var_of(s["rt"], "VY"), -4.0)

	# 只用核心时，用到扩展积木应该明确报错，而不是静默失败
	var s2 = build(ir, ["ee.core"])
	check("未启用扩展时不构建其实现", not s2["rt"].providers.has("ee.physics2d"))
	s2["rt"].green_flag()
	s2["rt"].step(0.1)
	check("未启用扩展时运行即报错", s2["rt"].errors.size() > 0, str(s2["rt"].errors))
	check("报错指明了扩展名",
		str(s2["rt"].errors).contains("ee.physics2d"), str(s2["rt"].errors))


func _check_unknown_op() -> void:
	group("未知 op 的失败方式")
	var ir = make_ir([
		node("A", [hat("flag", [
			op("完全不存在的.op", {}),
		])]),
	])
	var s = build(ir)
	s["rt"].green_flag()
	s["rt"].step(0.1)
	check("运行时错误被记录（不是崩溃）", s["rt"].errors.size() > 0, str(s["rt"].errors))
