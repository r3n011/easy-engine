# ee.core 的 op 实现。
#
# 约定：方法名 = "op_" + op id（把 "." 换成 "_"）。
# 运行时启动时会校验每个 op 都有对应方法（见 runtime.gd:verify_providers）。
#
# 注意控制流（repeat / if / while / warp）和让步（wait / wait_until）也在这里，
# 而不是在调度器里。它们通过 ctx.push_loop() / ctx.yield_time() 操作线程。
# 这就是"扩展也能写自己的控制流"的前提。
extends RefCounted

const Values = preload("res://ee/values.gd")
const OpContext = preload("res://ee/op_context.gd")

var runtime
var bridge

# pending 的询问（「询问并等待」用）
var _asking := false


# ============================================================ 事件

# 帽子积木本身不"执行"：它由 runtime.start_hats() 触发。
func op_event_hat(_ctx: OpContext, _op: Dictionary) -> void:
	pass


func op_event_broadcast(ctx: OpContext, op: Dictionary) -> void:
	ctx.start_hats("broadcast", { "message": ctx.eval("message") })


func op_event_broadcast_wait(ctx: OpContext, op: Dictionary) -> void:
	var ths: Array = ctx.start_hats("broadcast", { "message": ctx.eval("message") })
	if ths.is_empty():
		return
	ctx.yield_threads(ths)


# ============================================================ 控制

func op_control_repeat(ctx: OpContext, op: Dictionary) -> void:
	ctx.push_loop("repeat", op.get("body", []), Values.to_int_value(ctx.eval("times")))


func op_control_forever(ctx: OpContext, op: Dictionary) -> void:
	ctx.push_loop("forever", op.get("body", []))


func op_control_while(ctx: OpContext, op: Dictionary) -> void:
	ctx.push_loop("while", op.get("body", []), 0, op.get("cond"))


func op_control_if(ctx: OpContext, op: Dictionary) -> void:
	if Values.to_bool(ctx.eval("cond")):
		ctx.push_seq(op.get("body", []))


func op_control_if_else(ctx: OpContext, op: Dictionary) -> void:
	if Values.to_bool(ctx.eval("cond")):
		ctx.push_seq(op.get("then", []))
	else:
		ctx.push_seq(op.get("else", []))


func op_control_wait(ctx: OpContext, op: Dictionary) -> void:
	var secs := Values.to_number(ctx.eval("seconds"))
	if secs <= 0.0:
		# 等待 0 秒仍然让出一帧，这样「等待 0 秒」可以用来让出执行权
		ctx.yield_tick()
		return
	ctx.yield_time(secs)


func op_control_wait_until(ctx: OpContext, op: Dictionary) -> void:
	ctx.yield_until(op.get("cond"))


func op_control_stop(ctx: OpContext, op: Dictionary) -> void:
	match str(ctx.eval("mode")):
		"all":
			ctx.stop_all_threads()
		"other":
			ctx.stop_other_threads()
		_:
			ctx.stop_thread()


func op_control_stop_all(ctx: OpContext, _op: Dictionary) -> void:
	ctx.stop_all_threads()


func op_control_clone_create(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	runtime.clone_target(t)


func op_control_clone_delete(ctx: OpContext, _op: Dictionary) -> void:
	runtime.delete_clone(ctx.target)
	ctx.stop_thread()


func op_control_warp(ctx: OpContext, op: Dictionary) -> void:
	ctx.thread.enter_warp(runtime.now)
	ctx.push_warp(op.get("body", []))


# ============================================================ 运算（纯函数）

func op_op_add(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.add(ctx.eval("left"), ctx.eval("right"))

func op_op_sub(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.sub(ctx.eval("left"), ctx.eval("right"))

func op_op_mul(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.mul(ctx.eval("left"), ctx.eval("right"))

func op_op_div(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.div(ctx.eval("left"), ctx.eval("right"))

func op_op_mod(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.mod(ctx.eval("left"), ctx.eval("right"))

func op_op_round(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.round_to_nearest(ctx.eval("value"))

func op_op_abs(ctx: OpContext, op: Dictionary) -> Variant:
	return absf(Values.to_number(ctx.eval("value")))

func op_op_random(ctx: OpContext, op: Dictionary) -> Variant:
	var a := Values.to_number(ctx.eval("from"))
	var b := Values.to_number(ctx.eval("to"))
	if a == floor(a) and b == floor(b):
		var lo := int(a)
		var hi := int(b)
		if hi < lo:
			var t := lo
			lo = hi
			hi = t
		return float(randi_range(lo, hi))
	return randf_range(minf(a, b), maxf(a, b))

func op_op_gt(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.compare(ctx.eval("left"), ctx.eval("right")) > 0

func op_op_lt(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.compare(ctx.eval("left"), ctx.eval("right")) < 0

func op_op_eq(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.equals(ctx.eval("left"), ctx.eval("right"))

func op_op_and(ctx: OpContext, op: Dictionary) -> Variant:
	if not Values.to_bool(ctx.eval("left")):
		return false
	return Values.to_bool(ctx.eval("right"))

func op_op_or(ctx: OpContext, op: Dictionary) -> Variant:
	if Values.to_bool(ctx.eval("left")):
		return true
	return Values.to_bool(ctx.eval("right"))

func op_op_not(ctx: OpContext, op: Dictionary) -> Variant:
	return not Values.to_bool(ctx.eval("value"))

func op_op_join(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.to_string_value(ctx.eval("left")) + Values.to_string_value(ctx.eval("right"))

func op_op_letter_of(ctx: OpContext, op: Dictionary) -> Variant:
	var s := Values.to_string_value(ctx.eval("string"))
	var i := Values.to_int_value(ctx.eval("index"))
	# 第 1 个字符 = 下标 1；越界返回空串（Scratch 行为）
	if i < 1 or i > s.length():
		return ""
	return s[i - 1]

func op_op_length(ctx: OpContext, op: Dictionary) -> Variant:
	return float(Values.to_string_value(ctx.eval("string")).length())

func op_op_contains(ctx: OpContext, op: Dictionary) -> Variant:
	return Values.to_string_value(ctx.eval("string")).contains(Values.to_string_value(ctx.eval("needle")))

# 逃生舱①：受限表达式
func op_op_expression(ctx: OpContext, op: Dictionary) -> Variant:
	return runtime.eval_expression(Values.to_string_value(ctx.eval("source")), ctx.thread)


# ============================================================ 变量

func op_var_get(ctx: OpContext, op: Dictionary) -> Variant:
	return ctx.get_var(Values.to_string_value(ctx.eval("name")), str(ctx.eval("scope")))

func op_var_set(ctx: OpContext, op: Dictionary) -> void:
	ctx.set_var(Values.to_string_value(ctx.eval("name")), ctx.eval("value"), str(ctx.eval("scope")))

func op_var_change(ctx: OpContext, op: Dictionary) -> void:
	var name := Values.to_string_value(ctx.eval("name"))
	var scope := str(ctx.eval("scope"))
	var cur: Variant = ctx.get_var(name, scope)
	ctx.set_var(name, Values.number_result(Values.to_number(cur) + Values.to_number(ctx.eval("delta"))), scope)

func op_var_show(ctx: OpContext, op: Dictionary) -> void:
	bridge.set_monitor_visible(Values.to_string_value(ctx.eval("name")), false, Values.to_bool(ctx.eval("show")))


# ============================================================ 列表

func op_list_add(ctx: OpContext, op: Dictionary) -> void:
	ctx.get_list(Values.to_string_value(ctx.eval("name")), str(ctx.eval("scope"))).append(ctx.eval("value"))

func op_list_delete(ctx: OpContext, op: Dictionary) -> void:
	var arr := ctx.get_list(Values.to_string_value(ctx.eval("name")), str(ctx.eval("scope")))
	var i := Values.to_int_value(ctx.eval("index"))
	if i >= 1 and i <= arr.size():
		arr.remove_at(i - 1)

func op_list_clear(ctx: OpContext, op: Dictionary) -> void:
	ctx.get_list(Values.to_string_value(ctx.eval("name")), str(ctx.eval("scope"))).clear()

func op_list_insert(ctx: OpContext, op: Dictionary) -> void:
	var arr := ctx.get_list(Values.to_string_value(ctx.eval("name")), str(ctx.eval("scope")))
	var i := clampi(Values.to_int_value(ctx.eval("index")), 1, arr.size() + 1)
	arr.insert(i - 1, ctx.eval("value"))

func op_list_replace(ctx: OpContext, op: Dictionary) -> void:
	var arr := ctx.get_list(Values.to_string_value(ctx.eval("name")), str(ctx.eval("scope")))
	var i := Values.to_int_value(ctx.eval("index"))
	if i >= 1 and i <= arr.size():
		arr[i - 1] = ctx.eval("value")

func op_list_get(ctx: OpContext, op: Dictionary) -> Variant:
	var arr := ctx.get_list(Values.to_string_value(ctx.eval("name")), str(ctx.eval("scope")))
	var i := Values.to_int_value(ctx.eval("index"))
	if i < 1 or i > arr.size():
		return ""
	return arr[i - 1]

func op_list_length(ctx: OpContext, op: Dictionary) -> Variant:
	return float(ctx.get_list(Values.to_string_value(ctx.eval("name")), str(ctx.eval("scope"))).size())

func op_list_index_of(ctx: OpContext, op: Dictionary) -> Variant:
	var arr := ctx.get_list(Values.to_string_value(ctx.eval("name")), str(ctx.eval("scope")))
	var needle = ctx.eval("value")
	for i in arr.size():
		if Values.equals(arr[i], needle):
			return float(i + 1)
	return 0.0

func op_list_contains(ctx: OpContext, op: Dictionary) -> Variant:
	var arr := ctx.get_list(Values.to_string_value(ctx.eval("name")), str(ctx.eval("scope")))
	var needle = ctx.eval("value")
	for v in arr:
		if Values.equals(v, needle):
			return true
	return false

func op_list_show(ctx: OpContext, op: Dictionary) -> void:
	bridge.set_monitor_visible(Values.to_string_value(ctx.eval("name")), true, Values.to_bool(ctx.eval("show")))


# ============================================================ 运动
# Scratch 的方向约定：0 = 上，90 = 右，逆时针为正。
# 换算到 Godot：dx = sin(deg)，dy = -cos(deg)。

func _direction_of(t) -> float:
	return float(t.state.get("direction", 90.0))

func op_motion_move_steps(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var steps := Values.to_number(ctx.eval("steps"))
	var d := deg_to_rad(_direction_of(t))
	var pos: Vector2 = bridge.get_position(t)
	bridge.set_position(t, pos + Vector2(sin(d), -cos(d)) * steps)

func op_motion_set_position(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	bridge.set_position(t, Vector2(Values.to_number(ctx.eval("x")), Values.to_number(ctx.eval("y"))))

func op_motion_change_x(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var pos: Vector2 = bridge.get_position(t)
	bridge.set_position(t, Vector2(pos.x + Values.to_number(ctx.eval("dx")), pos.y))

func op_motion_change_y(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var pos: Vector2 = bridge.get_position(t)
	bridge.set_position(t, Vector2(pos.x, pos.y + Values.to_number(ctx.eval("dy"))))

func op_motion_set_x(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var pos: Vector2 = bridge.get_position(t)
	bridge.set_position(t, Vector2(Values.to_number(ctx.eval("x")), pos.y))

func op_motion_set_y(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var pos: Vector2 = bridge.get_position(t)
	bridge.set_position(t, Vector2(pos.x, Values.to_number(ctx.eval("y"))))

func op_motion_point_direction(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	t.state["direction"] = Values.to_number(ctx.eval("direction"))

func op_motion_turn(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var d := _direction_of(t)
	var delta := Values.to_number(ctx.eval("delta"))
	if str(ctx.eval("mode")) == "ccw":
		delta = -delta
	t.state["direction"] = d + delta

# 碰到边缘就反弹：按舞台边界反射，并把位置推回边界内
func op_motion_bounce(ctx: OpContext, _op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var half: Vector2 = bridge.get_stage_size() * 0.5
	var size: Vector2 = bridge.get_size(t)
	var pos: Vector2 = bridge.get_position(t)
	var d := _direction_of(t)
	var rad := deg_to_rad(d)
	var v := Vector2(sin(rad), -cos(rad))

	var hit_x := pos.x - size.x * 0.5 < -half.x or pos.x + size.x * 0.5 > half.x
	var hit_y := pos.y - size.y * 0.5 < -half.y or pos.y + size.y * 0.5 > half.y
	if hit_x:
		# 竖直墙面反射：方向取反（90 向右 → 270 向左；0 向上不变）
		d = -d
		pos.x = clampf(pos.x, -half.x + size.x * 0.5, half.x - size.x * 0.5)
	if hit_y:
		# 水平墙面反射：180 - d（0 向上 → 180 向下）
		d = 180.0 - d
		pos.y = clampf(pos.y, -half.y + size.y * 0.5, half.y - size.y * 0.5)
	if hit_x or hit_y:
		t.state["direction"] = d
		bridge.set_position(t, pos)

func op_motion_get_x(ctx: OpContext, _op: Dictionary) -> Variant:
	var t = ctx.resolve_target()
	return bridge.get_position(t).x if t != null else 0.0

func op_motion_get_y(ctx: OpContext, _op: Dictionary) -> Variant:
	var t = ctx.resolve_target()
	return bridge.get_position(t).y if t != null else 0.0

func op_motion_get_direction(ctx: OpContext, _op: Dictionary) -> Variant:
	var t = ctx.resolve_target()
	return _direction_of(t) if t != null else 0.0


# ============================================================ 外观

func op_looks_say(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	var text := Values.to_string_value(ctx.eval("text"))
	var secs := Values.to_number(ctx.eval("seconds"))
	bridge.show_say(t, text, str(ctx.eval("mode")), secs)
	if secs > 0.0:
		ctx.yield_time(secs)
		bridge.show_say(t, "", "", 0.0)

func op_looks_set_visible(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t != null:
		bridge.set_visible(t, Values.to_bool(ctx.eval("visible")))

func op_looks_set_costume(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	if str(ctx.eval("mode")) == "next":
		var list: Array = bridge.get_costumes(t)
		if list.is_empty():
			return
		var cur := str(t.state.get("costume", ""))
		var idx := 0
		for i in list.size():
			if str(list[i].get("name", "")) == cur:
				idx = i
				break
		bridge.set_costume(t, str(list[(idx + 1) % list.size()].get("name", "")))
	else:
		bridge.set_costume(t, Values.to_string_value(ctx.eval("name")))

func op_looks_set_size(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var cur: float = bridge.get_scale_percent(t)
	var v := Values.to_number(ctx.eval("percent"))
	if str(ctx.eval("mode")) == "change":
		bridge.set_scale_percent(t, cur + v)
	else:
		bridge.set_scale_percent(t, v)

func op_looks_set_effect(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var effect := Values.to_string_value(ctx.eval("effect"))
	var v := Values.to_number(ctx.eval("value"))
	if str(ctx.eval("mode")) == "change":
		var fx: Dictionary = t.state.get("effects", {})
		v = float(fx.get(effect, 0.0)) + v
	bridge.set_effect(t, effect, v)

func op_looks_clear_effects(ctx: OpContext, _op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t != null:
		bridge.clear_effects(t)

func op_looks_set_layer(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t != null:
		bridge.set_layer(t, str(ctx.eval("mode")), int(Values.to_number(ctx.eval("layers"))))


# ============================================================ 声音

func op_sound_play(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	var name := Values.to_string_value(ctx.eval("name"))
	var wait := Values.to_bool(ctx.eval("wait"))
	bridge.play_sound(t, name, wait)
	# 无渲染环境里没有真实时长，等到下一帧就当作"播完了"
	if wait:
		ctx.yield_tick()

func op_sound_stop_all(ctx: OpContext, _op: Dictionary) -> void:
	bridge.stop_all_sounds()


# ============================================================ 侦测

func op_sensing_touching(ctx: OpContext, op: Dictionary) -> Variant:
	var t = ctx.resolve_target()
	if t == null:
		return false
	return bridge.is_touching(t, ctx.eval("other"))

func op_sensing_key_pressed(ctx: OpContext, op: Dictionary) -> Variant:
	return bridge.is_key_pressed(Values.to_string_value(ctx.eval("key")))

func op_sensing_mouse_x(ctx: OpContext, _op: Dictionary) -> Variant:
	return bridge.get_mouse_position().x

func op_sensing_mouse_y(ctx: OpContext, _op: Dictionary) -> Variant:
	return bridge.get_mouse_position().y

func op_sensing_mouse_down(ctx: OpContext, _op: Dictionary) -> Variant:
	return bridge.is_mouse_pressed()

func op_sensing_timer(ctx: OpContext, _op: Dictionary) -> Variant:
	return runtime.timer_value()

func op_sensing_reset_timer(ctx: OpContext, _op: Dictionary) -> void:
	runtime.reset_timer()

func op_sensing_ask(ctx: OpContext, op: Dictionary) -> void:
	if not _asking:
		bridge.ask(Values.to_string_value(ctx.eval("question")))
		_asking = true
	if bridge.answer_ready():
		runtime.answer = bridge.get_answer()
		_asking = false
		return
	# 还没回答：让出这一帧，下一帧重新执行这条 op
	ctx.rewind()
	ctx.yield_tick()

func op_sensing_answer(ctx: OpContext, _op: Dictionary) -> Variant:
	return runtime.answer


# ============================================================ 元积木

func op_meta_set_property(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t != null:
		bridge.set_property(t, Values.to_string_value(ctx.eval("property")), ctx.eval("value"))

func op_meta_get_property(ctx: OpContext, op: Dictionary) -> Variant:
	var t = ctx.resolve_target()
	if t == null:
		return null
	return bridge.get_property(t, Values.to_string_value(ctx.eval("property")))

func op_meta_call_method(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t != null:
		bridge.call_method(t, Values.to_string_value(ctx.eval("method")), ctx.eval("args"))

func op_meta_emit_signal(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t != null:
		bridge.emit_signal_to(t, Values.to_string_value(ctx.eval("signal")), ctx.eval("args"))

func op_meta_instantiate(ctx: OpContext, op: Dictionary) -> void:
	bridge.instantiate(ctx.resolve_target(), Values.to_string_value(ctx.eval("source")))


# ============================================================ 代码块（逃生舱②）

func op_code_gdscript(ctx: OpContext, op: Dictionary) -> void:
	bridge.run_code(ctx.resolve_target(), Values.to_string_value(ctx.eval("source")))
