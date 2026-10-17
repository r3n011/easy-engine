# OpContext：op 实现与调度器之间唯一的接口。
#
# 这个类是"调度器保持通用"的关键：控制流（repeat/if/while/warp）和让步（wait…）
# 都不是调度器的特例，而是 core provider 里普通 op 实现——
# 它们通过 ctx.push_loop / ctx.yield_* 来操作线程。
# 于是扩展也能写出自己的控制流与让步语义。
extends RefCounted

var runtime
var thread
var target
var op: Dictionary = {}

func bind(p_runtime, p_thread, p_op: Dictionary) -> void:
	runtime = p_runtime
	thread = p_thread
	target = thread.target if thread != null else null
	op = p_op

# ---- 取参数 -----------------------------------------------------------

# 求值一个参数（可能是字面量，也可能是嵌套的表达式 op）
func eval(arg_name: String) -> Variant:
	return runtime.eval_value(thread, op.get(arg_name, null))

func raw(arg_name: String) -> Variant:
	return op.get(arg_name, null)

# 解析 op 的 target 字段，得到 Target 实例
func resolve_target() -> Variant:
	return runtime.resolve_target(thread, op.get("target", "@self"))

# 解析一个"节点引用"参数（用于「碰到 X」这类）
func resolve_node_arg(arg_name: String) -> Variant:
	return runtime.resolve_reference(eval(arg_name), thread)

# ---- 控制流：操作线程的帧栈 -------------------------------------------

func push_seq(ops: Array) -> void:
	if ops.is_empty():
		return
	thread.push({ "ops": ops, "idx": 0, "loop": "", "left": 0, "cond": null, "warp": false })

func push_loop(kind: String, ops: Array, count := 0, cond: Variant = null) -> void:
	if ops.is_empty():
		return
	# repeat 0 次直接跳过
	if kind == "repeat" and count <= 0:
		return
	thread.push({
		"ops": ops, "idx": 0, "loop": kind,
		"left": count, "cond": cond, "warp": false,
	})

# 原子执行：body 内循环不再让步
func push_warp(ops: Array) -> void:
	if ops.is_empty():
		return
	thread.push({ "ops": ops, "idx": 0, "loop": "warp", "left": 0, "cond": null, "warp": true })

# 结束当前脚本 / 结束全部
func stop_thread() -> void:
	thread.finish()

func stop_all_threads() -> void:
	runtime.stop_all()

func stop_other_threads() -> void:
	runtime.stop_other_threads(thread)

# ---- 让步 -------------------------------------------------------------

func yield_tick() -> void:
	thread.yield_tick()

# 让当前 op 下一帧再执行一次（用于"还没好，再来一次"这类逻辑）
func rewind() -> void:
	var f: Dictionary = thread.top()
	if not f.is_empty() and int(f["idx"]) > 0:
		f["idx"] = int(f["idx"]) - 1

func yield_time(seconds: float) -> void:
	thread.yield_time(runtime.now + maxf(0.0, seconds))

func yield_until(cond: Variant) -> void:
	thread.yield_until(cond)

func yield_threads(threads: Array) -> void:
	thread.yield_threads(threads)

# ---- 事件 -------------------------------------------------------------

# 启动一组帽子脚本。返回被启动的线程（供「广播并等待」使用）
func start_hats(kind: String, params: Dictionary = {}) -> Array:
	return runtime.start_hats(kind, params)

# ---- 变量 -------------------------------------------------------------

func get_var(name: String, scope := "auto") -> Variant:
	return runtime.get_var(name, scope, target)

func set_var(name: String, value: Variant, scope := "auto") -> void:
	runtime.set_var(name, value, scope, target)

func get_list(name: String, scope := "auto") -> Array:
	return runtime.get_list(name, scope, target)

# ---- 诊断 -------------------------------------------------------------

func warn(message: String) -> void:
	runtime.warn("[" + thread.describe() + "] " + message)

func fail(message: String) -> void:
	thread.fail(message)
