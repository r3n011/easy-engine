# Runtime：调度器。整个积木语言的运行核心。
#
# 每帧做四件事：
#   1. 让等待条件已满足的线程恢复
#   2. 逐个执行可运行的线程，一直到它让步或结束
#   3. 回收结束的线程
#   4. （克隆体、广播由 op 通过 ctx 触发）
#
# 调度器**不认识任何具体 op**：它只做"取下一个 op → 交给 provider"。
# 控制流与让步语义都由 provider 通过 OpContext 实现（见 op_context.gd）。
# 这样扩展可以引入自己的控制流和挂起语义，不需要改这里。
extends RefCounted

const Values = preload("res://ee/values.gd")
const ThreadClass = preload("res://ee/thread.gd")
const Target = preload("res://ee/target.gd")
const OpContext = preload("res://ee/op_context.gd")
const Expr = preload("res://ee/expr.gd")

# 单帧单线程的 op 预算：防止「一个不让步的死循环」把程序卡死。
# 触发后强制让步到下一帧，并记一次告警。
const MAX_OPS_PER_FRAME := 2000000

# warp 内超过这个秒数就强制让步（对应 Scratch 的 warp timer）
const WARP_TIME_LIMIT := 0.5

# 克隆体上限
var max_clones := 300

var registry
var bridge
var providers := {}

var targets := []
var targets_by_id := {}
var threads := []

var globals := {}
var global_lists := {}

var now := 0.0
var frame := 0
var timer_base := 0.0
var answer := ""

var errors := []
var warnings := []

var _ctx
var _expr_cache := {}
var _started_hats := []


func setup(p_registry, p_bridge) -> void:
	registry = p_registry
	bridge = p_bridge
	if bridge != null:
		bridge.runtime = self
	providers.clear()
	errors.clear()
	warnings.clear()
	_ctx = OpContext.new()
	_ctx.runtime = self
	_build_providers()
	verify_providers()


# 为每个扩展构造 provider，并校验"每个 op 都有实现"。
# 这一步能在启动时抓住"扩展加了 op 却忘了写实现"，而不是跑到那一行才崩。
func _build_providers() -> void:
	for eid in registry.extensions:
		# 未启用的扩展不构建实现：用它就是错，且要报得清楚
		if not registry.is_ext_enabled(eid):
			continue
		var provider_path := str(registry.extensions[eid].get("provider", ""))
		if provider_path == "":
			continue
		if not ResourceLoader.exists(provider_path):
			errors.append("扩展 %s 声明的 provider 不存在：%s" % [eid, provider_path])
			continue
		var script: GDScript = load(provider_path)
		if script == null:
			errors.append("扩展 %s 的 provider 不是脚本：%s" % [eid, provider_path])
			continue
		var inst = script.new()
		inst.runtime = self
		inst.bridge = bridge
		providers[eid] = inst


func verify_providers() -> void:
	for oid in registry.ops:
		var def: Dictionary = registry.ops[oid]
		if not bool(def.get("enabled", true)):
			continue
		var eid: String = str(def.get("extension", ""))
		var provider = providers.get(eid)
		if provider == null:
			errors.append("op %s 属于扩展 %s，但该扩展没有 provider" % [oid, eid])
			continue
		var method: String = "op_" + oid.replace(".", "_")
		if not provider.has_method(method):
			errors.append("op %s 没有实现（%s 里缺少 %s()）" % [oid, provider.get_script().resource_path, method])


# ---- 装载 IR ----------------------------------------------------------

func load_ir(ir: Dictionary) -> void:
	targets.clear()
	targets_by_id.clear()
	threads.clear()
	globals.clear()
	global_lists.clear()
	errors.clear()
	warnings.clear()
	now = 0.0
	frame = 0
	timer_base = 0.0
	Target.reset_clone_counter()

	var g: Dictionary = ir.get("globals", {})
	for v in g.get("variables", []):
		globals[str(v.get("name", ""))] = v.get("value", null)
	for l in g.get("lists", []):
		global_lists[str(l.get("name", ""))] = (l.get("value", []) as Array).duplicate(true)

	for n in ir.get("nodes", []):
		var t = Target.from_node(n)
		targets.append(t)
		targets_by_id[t.id] = t
		bridge.create_visual(t)


# ---- 事件 -------------------------------------------------------------

# 启动所有匹配的帽子脚本，返回被启动的线程。
# kind: flag / key / broadcast / clone_start / touching
func start_hats(kind: String, params: Dictionary = {}) -> Array:
	var started: Array = []
	for t in targets:
		if not t.alive:
			continue
		for script in t.scripts:
			if str(script.get("op", "")) != "event.hat":
				continue
			if str(script.get("kind", "")) != kind:
				continue
			if not _hat_params_match(script, params):
				continue
			var body: Array = script.get("body", [])
			if body.is_empty():
				continue
			var th = ThreadClass.create(t, [{ "ops": body, "idx": 0, "loop": "", "left": 0, "cond": null, "warp": false }], true)
			th.hat_kind = kind
			t.threads.append(th)
			threads.append(th)
			started.append(th)
	return started


func _hat_params_match(script: Dictionary, params: Dictionary) -> bool:
	var raw: Variant = script.get("params", {})
	var sp: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	for key in params:
		if not sp.has(key):
			continue
		if not Values.equals(sp[key], params[key]):
			return false
	return true


func green_flag() -> Array:
	timer_base = now
	return start_hats("flag", {})


# ---- 主循环 -----------------------------------------------------------

func step(delta: float = 1.0 / 60.0) -> void:
	now += delta
	frame += 1

	# 1. 恢复等待条件已满足的线程
	for t in threads:
		if t.is_done():
			continue
		match t.status:
			ThreadClass.Status.YIELD_TICK:
				t.resume()
			ThreadClass.Status.YIELD_TIME:
				if now >= t.resume_at:
					t.resume()
			ThreadClass.Status.YIELD_UNTIL:
				if Values.to_bool(eval_value(t, t.wait_cond)):
					t.resume()
			ThreadClass.Status.YIELD_THREADS:
				if _all_finished(t.wait_threads):
					t.resume()

	# 2. 执行
	# 用快照遍历：本帧内新启动的线程（广播、克隆体）留到下一帧再跑。
	# 这样"一帧内发生什么"是可预测的，帧计数也能稳定断言。
	var snapshot: Array = threads.duplicate()
	for t in snapshot:
		if t.status != ThreadClass.Status.RUNNING:
			continue
		t.reset_frame_budget(MAX_OPS_PER_FRAME)
		_step_thread(t)

	# 3. 回收
	_reap()


func run_frames(n: int, delta: float = 1.0 / 60.0) -> void:
	for i in n:
		step(delta)


func _reap() -> void:
	var keep: Array = []
	for t in threads:
		if t.is_done():
			if t.status == ThreadClass.Status.ERROR:
				errors.append(t.error_message)
			if t.target != null:
				t.target.threads.erase(t)
			continue
		keep.append(t)
	threads = keep


func _all_finished(list: Array) -> bool:
	for t in list:
		if not t.is_done():
			return false
	return true


# ---- 单线程执行 -------------------------------------------------------

func _step_thread(t) -> void:
	while t.status == ThreadClass.Status.RUNNING:
		if t.budget_left() <= 0:
			# 不让步的死循环：强制让步并告警（这是保护，不是正常路径）
			warnings.append("单帧执行超出预算，已强制让步。检查是否有不让步的死循环。\n" + t.describe())
			t.yield_tick()
			return

		# warp 超时保护：防止「不刷新屏幕」真的把程序冻住
		if t.in_warp() and (now - t.warp_started) > WARP_TIME_LIMIT:
			t.warp_started = now
			t.yield_tick()
			return

		var f: Dictionary = t.top()
		if f.is_empty():
			t.finish()
			return

		if int(f["idx"]) >= (f["ops"] as Array).size():
			_close_iteration(t, f)
			continue

		var op: Dictionary = (f["ops"] as Array)[int(f["idx"])]
		f["idx"] = int(f["idx"]) + 1
		t.tick_op()
		_dispatch(t, op)


# 一轮走完：决定是"结束这一帧/这一次迭代"还是"再跑一轮"
func _close_iteration(t, f: Dictionary) -> void:
	match str(f["loop"]):
		"":
			t.pop()          # 普通顺序块，弹栈继续（不消耗帧）
		"repeat":
			f["left"] = int(f["left"]) - 1
			if int(f["left"]) > 0:
				f["idx"] = 0
				_loop_yield(t)
			else:
				t.pop()
		"forever":
			f["idx"] = 0
			_loop_yield(t)
		"while":
			if Values.to_bool(eval_value(t, f["cond"])):
				f["idx"] = 0
				_loop_yield(t)
			else:
				t.pop()
		"warp":
			t.pop()
			t.exit_warp()


# 循环每轮结束是否让步：warp 内不让步，否则让到下一帧。
# 这正是「重复执行 10 次 移动 10 步」会花 10 帧的原因——与 Scratcher 的直觉一致。
func _loop_yield(t) -> void:
	if t.in_warp():
		return
	t.yield_tick()


# ---- op 派发 ----------------------------------------------------------

func _dispatch(t, op: Dictionary) -> Variant:
	var oid := str(op.get("op", ""))
	if oid == "":
		return null
	if not registry.has_op(oid):
		t.fail("未知 op：%s（IR 与运行时版本不匹配？）" % oid)
		return null
	var def: Dictionary = registry.ops[oid]
	if not bool(def.get("enabled", true)):
		t.fail("积木用到的扩展 %s 未启用（op %s）" % [def.get("extension", "?"), oid])
		return null
	var eid := str(def.get("extension", ""))
	var provider = providers.get(eid)
	if provider == null:
		t.fail("op %s 所属扩展 %s 没有 provider" % [oid, eid])
		return null
	var method: String = "op_" + oid.replace(".", "_")
	if not provider.has_method(method):
		t.fail("op %s 没有实现（缺少 %s）" % [oid, method])
		return null

	# ★ 保存并恢复上下文：求值嵌套表达式时会递归进入 _dispatch，
	#   如果共用同一个 _ctx 而不恢复，外层的 op/target 会被内层覆盖，
	#   于是「移到 x: 鼠标x y: -140」里的 y 会读到错的对象（变成 0）。
	#   这个 bug 只有真的用嵌套积木才会暴露，是回归测试盯的一个点。
	var saved_op: Dictionary = _ctx.op
	var saved_target = _ctx.target
	_ctx.bind(self, t, op)
	var result: Variant = provider.call(method, _ctx, op)
	_ctx.op = saved_op
	_ctx.target = saved_target
	return result


# 求值一个"值位置"的 IR：字面量直接返回，表达式 op 走派发
func eval_value(t, v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY and v.has("op") and t != null:
		return _dispatch(t, v)
	return v


# ---- 引用解析 ---------------------------------------------------------

# target 字段 -> Target 实例
func resolve_target(t, ref: Variant) -> Variant:
	if typeof(ref) == TYPE_STRING:
		return resolve_reference(ref, t)
	if typeof(ref) == TYPE_DICTIONARY and ref.has("op"):
		return resolve_reference(eval_value(t, ref), t)
	return null


func resolve_reference(ref: Variant, t) -> Variant:
	var s := str(ref)
	match s:
		"@self":
			return t.target if t != null else null
		"@stage":
			return null          # 舞台用 targets_by_id 里没有的根；M3 接 Godot 后返回舞台节点
		"@mouse", "@any_sprite":
			return null          # 仅用于侦测，不作为可操作对象
	if targets_by_id.has(s):
		return targets_by_id[s]
	return null


# ---- 变量 -------------------------------------------------------------

func get_var(name: String, scope: String, t) -> Variant:
	if scope == "global":
		return globals.get(name, 0)
	if scope == "local":
		return t.vars.get(name, 0) if t != null else 0
	# auto：先找局部，再找全局 —— 这样克隆体的局部变量能正确遮蔽全局变量
	if t != null and t.vars.has(name):
		return t.vars[name]
	return globals.get(name, 0)


func set_var(name: String, value: Variant, scope: String, t) -> void:
	if scope == "global":
		globals[name] = value
		return
	if scope == "local":
		if t != null:
			t.vars[name] = value
		return
	if t != null and t.vars.has(name):
		t.vars[name] = value
	else:
		globals[name] = value


func get_list(name: String, scope: String, t) -> Array:
	if scope == "global":
		if not global_lists.has(name):
			global_lists[name] = []
		return global_lists[name]
	if scope == "local":
		if t != null:
			if not t.lists.has(name):
				t.lists[name] = []
			return t.lists[name]
		return []
	if t != null and t.lists.has(name):
		return t.lists[name]
	if not global_lists.has(name):
		global_lists[name] = []
	return global_lists[name]


# 供表达式求值器查变量
func lookup_name(name: String, t) -> Variant:
	return get_var(name, "auto", t)


# ---- 表达式（逃生舱①）------------------------------------------------

# 编译并缓存表达式；同一段表达式在循环里不会重复解析
func eval_expression(source: String, t) -> Variant:
	var core: Dictionary = _expr_cache.get(source, {})
	if core.is_empty():
		core = Expr.compile(source)
		_expr_cache[source] = core
	if not core["ok"]:
		if t != null:
			t.fail("表达式有错：%s（在第 %d 个字符附近）" % [core["error"], int(core["pos"]) + 1])
		return null
	return Expr.evaluate(core["ast"], func(n): return lookup_name(n, t))


# ---- 线程控制 ---------------------------------------------------------

func stop_all() -> void:
	for t in threads:
		t.kill()
	threads.clear()


func stop_other_threads(keep) -> void:
	for t in threads:
		if t != keep:
			t.kill()
	var rest: Array = [keep] if not keep.is_done() else []
	threads = rest


func stop_target_threads(target) -> void:
	var keep: Array = []
	for t in threads:
		if t.target == target:
			t.kill()
		else:
			keep.append(t)
	threads = keep


# ---- 克隆 -------------------------------------------------------------

func clone_target(src) -> Variant:
	if src == null:
		return null
	var count := 0
	for t in targets:
		if t.is_clone:
			count += 1
	if count >= max_clones:
		warn("克隆体数量已达上限 %d，忽略本次克隆" % max_clones)
		return null
	var c = bridge.clone_visual(src)
	targets.append(c)
	targets_by_id[c.id] = c
	bridge.create_visual(c)
	# 克隆体启动时触发一次 clone_start 帽子
	for script in c.scripts:
		if str(script.get("op", "")) == "event.hat" and str(script.get("kind", "")) == "clone_start":
			var body: Array = script.get("body", [])
			if not body.is_empty():
				var th = ThreadClass.create(c, [{ "ops": body, "idx": 0, "loop": "", "left": 0, "cond": null, "warp": false }], true)
				th.hat_kind = "clone_start"
				c.threads.append(th)
				threads.append(th)
	return c


func delete_clone(t) -> void:
	if t == null or not t.is_clone:
		return
	t.alive = false
	stop_target_threads(t)
	bridge.destroy_visual(t)
	targets.erase(t)
	targets_by_id.erase(t.id)


# ---- 计时器 -----------------------------------------------------------

func timer_value() -> float:
	return now - timer_base


func reset_timer() -> void:
	timer_base = now


# ---- 诊断 -------------------------------------------------------------

func warn(message: String) -> void:
	if warnings.size() < 200:
		warnings.append(message)


func live_thread_count() -> int:
	return threads.size()


# 卸载项目 / 释放运行时。
#
# 为什么必须显式做：Thread.target 与 Target.threads 互相强引用形成环，
# GDScript 的 RefCounted 没有环回收，不打断就会泄漏。
# 长时间反复加载项目（编辑器预览）时这会累积。
func dispose() -> void:
	for t in targets:
		if t != null:
			t.threads.clear()
	for th in threads:
		th.target = null
		th.frames.clear()

	threads.clear()
	targets.clear()
	targets_by_id.clear()
	providers.clear()
	_expr_cache.clear()
	# _ctx.runtime 指回本对象，也是一个环
	if _ctx != null:
		_ctx.runtime = null
		_ctx.thread = null
		_ctx.target = null
		_ctx = null


func describe_state() -> String:
	return "帧 %d，时间 %.3fs，目标 %d 个，活动线程 %d 个" % [frame, now, targets.size(), threads.size()]
