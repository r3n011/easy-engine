# 节点桥：IR 里的 op 与"真实 Godot 节点"之间的唯一隔层。
#
# 为什么要这一层：
#   * M2 要先把调度器跑通并测出来，此时还没有渲染；
#   * M3 接 Godot 节点时，只换实现，调度器与 op 实现一行不改；
#   * 测试可以断言"桥收到了什么调用"，这是验证语义最省事的办法。
#
# 约定：所有方法都接受 target（Target 实例），不认识的操作返回 null 并登记一次告警，
# 而不是直接崩——积木项目里出现"桥暂时不支持"是可接受的降级。
extends RefCounted

var calls: Array = []          # 调用日志，测试用：[{ method, target, args }]
var warnings: Array = []
var runtime = null             # 由 Runtime.setup() 注入，供需要解析引用的实现使用

func _log(method: String, target, args: Array) -> void:
	calls.append({ "method": method, "target": target.id if target != null else "", "args": args })

# 测试辅助：取出某个方法的调用记录
func calls_of(method: String) -> Array:
	var out: Array = []
	for c in calls:
		if c["method"] == method:
			out.append(c)
	return out

func clear_log() -> void:
	calls.clear()

# ---- 生命周期 ---------------------------------------------------------

func create_visual(_target) -> void:
	_log("create_visual", _target, [])

func destroy_visual(_target) -> void:
	_log("destroy_visual", _target, [])

# ---- 位置 / 变换 ------------------------------------------------------

func get_position(target) -> Vector2:
	_log("get_position", target, [])
	return target.state.get("position", Vector2.ZERO)

func set_position(target, pos: Vector2) -> void:
	_log("set_position", target, [pos])
	target.state["position"] = pos

func get_rotation(target) -> float:
	_log("get_rotation", target, [])
	return float(target.state.get("rotation", 0.0))

func set_rotation(target, radians_: float) -> void:
	_log("set_rotation", target, [radians_])
	target.state["rotation"] = radians_

# 方向用 Scratch 约定（0=上 90=右）。视觉层负责换算成自己的角度。
func get_direction(target) -> float:
	_log("get_direction", target, [])
	return float(target.state.get("direction", 90.0))

func set_direction(target, degrees: float) -> void:
	_log("set_direction", target, [degrees])
	target.state["direction"] = degrees

func get_scale_percent(target) -> float:
	_log("get_scale_percent", target, [])
	return float(target.state.get("scale_percent", 100.0))

func set_scale_percent(target, percent: float) -> void:
	_log("set_scale_percent", target, [percent])
	target.state["scale_percent"] = percent

# 角色包围盒（碰边反弹、碰撞检测要用）
func get_size(target) -> Vector2:
	_log("get_size", target, [])
	return target.state.get("size", Vector2(32, 32))

func set_size(target, s: Vector2) -> void:
	target.state["size"] = s

# ---- 外观 -------------------------------------------------------------

func set_visible(target, v: bool) -> void:
	_log("set_visible", target, [v])
	target.state["visible"] = v

func get_visible(target) -> bool:
	_log("get_visible", target, [])
	return bool(target.state.get("visible", true))

func set_costume(target, name: String) -> void:
	_log("set_costume", target, [name])
	target.state["costume"] = name

func get_costumes(target) -> Array:
	return target.costumes

func set_effect(target, effect: String, value: float) -> void:
	_log("set_effect", target, [effect, value])
	var fx: Dictionary = target.state.get("effects", {})
	fx[effect] = value
	target.state["effects"] = fx

func clear_effects(target) -> void:
	_log("clear_effects", target, [])
	target.state["effects"] = {}

func set_layer(target, mode: String, layers: int) -> void:
	_log("set_layer", target, [mode, layers])

# ---- 声音 -------------------------------------------------------------

func play_sound(target, name: String, wait: bool) -> void:
	_log("play_sound", target, [name, wait])

func stop_all_sounds() -> void:
	_log("stop_all_sounds", null, [])

# ---- 舞台 / 侦测 ------------------------------------------------------

func get_stage_size() -> Vector2:
	return Vector2(480, 360)

func is_touching(target, other: Variant) -> bool:
	_log("is_touching", target, [other])
	return false

func is_key_pressed(key: String) -> bool:
	_log("is_key_pressed", null, [key])
	return false

func get_mouse_position() -> Vector2:
	_log("get_mouse_position", null, [])
	return Vector2.ZERO

func is_mouse_pressed() -> bool:
	_log("is_mouse_pressed", null, [])
	return false

func show_say(target, text: String, mode: String, seconds: float) -> void:
	_log("show_say", target, [text, mode, seconds])

func ask(question: String) -> void:
	_log("ask", null, [question])

func get_answer() -> String:
	return _pending_answer

# 无渲染环境下"回答"总是就绪的（测试可以直接预设）
func answer_ready() -> bool:
	return _answer_ready

var _pending_answer := ""
var _answer_ready := true

# 测试用：预设下一次询问的回答
func preset_answer(text: String) -> void:
	_pending_answer = text
	_answer_ready = true

# ---- 监视器（显示变量/列表）------------------------------------------

func set_monitor_visible(name: String, is_list: bool, show: bool) -> void:
	_log("set_monitor_visible", null, [name, is_list, show])

# ---- 元积木（通用逃生舱）----------------------------------------------

func set_property(target, property: String, value: Variant) -> void:
	_log("set_property", target, [property, value])
	target.state["prop:" + property] = value

func get_property(target, property: String) -> Variant:
	_log("get_property", target, [property])
	return target.state.get("prop:" + property, null)

func call_method(target, method: String, args: Array) -> Variant:
	_log("call_method", target, [method, args])
	return null

func emit_signal_to(target, signal_name: String, args: Array) -> void:
	_log("emit_signal_to", target, [signal_name, args])

func instantiate(parent, source: String):
	_log("instantiate", parent, [source])
	return null

# 物理查询：无渲染环境里恒为 false（M3 接 Godot 后走真物理）
func raycast_hit(target, direction: float, distance: float) -> bool:
	_log("raycast_hit", target, [direction, distance])
	return false

# ---- 克隆 -------------------------------------------------------------

func clone_visual(target):
	_log("clone_visual", target, [])
	return target.duplicate_target()

# ---- 代码块（逃生舱②）------------------------------------------------

func run_code(target, source: String) -> void:
	_log("run_code", target, [source])
	_execute_code(target, source)


# 默认实现：**明确告警而不是静默忽略**——否则用户会以为代码跑了。
# 真实实现在 GodotBridge 里覆写（见 _execute_code）。
func _execute_code(_target, _source: String) -> void:
	warnings.append("当前环境不支持「执行代码」积木（内容已记录，未执行）")
