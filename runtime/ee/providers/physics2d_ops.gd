# ee.physics2d 的 op 实现。
#
# 存在的意义有两点：
#   1. M6 物理积木的实现起点；
#   2. 证明「扩展自己写 provider」这条机制成立——
#      这个文件完全独立于引擎，新增它没有改动任何核心代码。
#
# M2 阶段没有真实物理，速度按帧累积到 state 里，足够验证语义与调度。
extends RefCounted

const Values = preload("res://ee/values.gd")
const OpContext = preload("res://ee/op_context.gd")

var runtime
var bridge


func _vel(t) -> Vector2:
	return t.state.get("velocity", Vector2.ZERO)


func _set_vel(t, v: Vector2) -> void:
	t.state["velocity"] = v


func op_vec2(ctx: OpContext, op: Dictionary) -> Variant:
	return Vector2(Values.to_number(ctx.eval("x")), Values.to_number(ctx.eval("y")))


func op_phy2d_apply_impulse(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var impulse: Variant = ctx.eval("impulse")
	if typeof(impulse) != TYPE_VECTOR2:
		return
	_set_vel(t, _vel(t) + impulse / maxf(1.0, float(t.state.get("mass", 1.0))))


func op_phy2d_set_velocity(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t == null:
		return
	var v: Variant = ctx.eval("velocity")
	if typeof(v) == TYPE_VECTOR2:
		_set_vel(t, v)


func op_phy2d_set_gravity_scale(ctx: OpContext, op: Dictionary) -> void:
	var t = ctx.resolve_target()
	if t != null:
		t.state["gravity_scale"] = Values.to_number(ctx.eval("scale"))


func op_phy2d_get_velocity_x(ctx: OpContext, _op: Dictionary) -> Variant:
	var t = ctx.resolve_target()
	return _vel(t).x if t != null else 0.0


func op_phy2d_get_velocity_y(ctx: OpContext, _op: Dictionary) -> Variant:
	var t = ctx.resolve_target()
	return _vel(t).y if t != null else 0.0


func op_phy2d_is_on_floor(ctx: OpContext, _op: Dictionary) -> Variant:
	var t = ctx.resolve_target()
	return bool(t.state.get("on_floor", false)) if t != null else false


func op_phy2d_raycast_hit(ctx: OpContext, op: Dictionary) -> Variant:
	var t = ctx.resolve_target()
	if t == null:
		return false
	# M2 没有真实物理查询；交给桥，桥在无渲染环境里返回 false。
	return bridge.raycast_hit(t, Values.to_number(ctx.eval("direction")), Values.to_number(ctx.eval("distance")))
