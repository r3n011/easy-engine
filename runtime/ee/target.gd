# Target：脚本作用的对象。对应 .ee 里一个节点，或它的一个克隆体。
#
# 与 Scratch 的对应：
#   原型（is_clone = false） = 角色
#   克隆体（is_clone = true） = 克隆体，局部变量是原型的副本
extends RefCounted

var id := ""                 # 节点 id（克隆体是 "Player#3" 这样的运行时 id）
var prototype_id := ""       # 原型节点的 id
var name := ""
var template := "SPRITE_2D"
var is_clone := false
var order := 0

var costumes := []
var sounds := []

var vars := {}               # 局部变量 name -> value
var lists := {}              # 局部列表 name -> Array

var state := {}              # 桥自己用的可视状态（位置/大小/特效…）
var scripts := []            # IR：这个目标拥有的脚本（帽子 op 的数组）

# 运行时
var alive := true
var threads := []            # 属于它的线程


static func from_node(node: Dictionary) -> RefCounted:
	var t = new()
	t.id = str(node.get("id", ""))
	t.prototype_id = t.id
	t.name = str(node.get("name", t.id))
	t.template = str(node.get("template", "SPRITE_2D"))
	t.order = int(node.get("order", 0))
	t.costumes = node.get("costumes", [])
	t.sounds = node.get("sounds", [])
	t.scripts = node.get("scripts", [])

	for v in node.get("localVariables", []):
		t.vars[str(v.get("name", ""))] = _value_of(v)

	var tr: Dictionary = node.get("transform", {})
	var pos: Array = tr.get("position", [0, 0])
	var sc: Array = tr.get("scale", [100, 100])
	t.state["position"] = Vector2(float(pos[0]), float(pos[1]))
	t.state["rotation"] = float(tr.get("rotation", 0))
	t.state["scale_percent"] = float(sc[0])
	t.state["visible"] = bool(node.get("visible", true))
	t.state["costume"] = str(t.costumes[0].get("name", "")) if not t.costumes.is_empty() else ""
	t.state["effects"] = {}
	return t


static func _value_of(entry: Dictionary) -> Variant:
	return entry.get("value", null)


# 克隆：局部变量与局部列表做副本（与 Scratch 的克隆体语义一致）
func duplicate_target():
	var c = new()
	c.id = "%s#%d" % [prototype_id, _next_clone_index()]
	c.prototype_id = prototype_id
	c.name = name
	c.template = template
	c.is_clone = true
	c.order = order
	c.costumes = costumes.duplicate(true)
	c.sounds = sounds.duplicate(true)
	c.vars = vars.duplicate(true)
	c.lists = lists.duplicate(true)
	c.state = state.duplicate(true)
	c.scripts = scripts
	return c


static var _clone_counter := 0

static func _next_clone_index() -> int:
	_clone_counter += 1
	return _clone_counter


static func reset_clone_counter() -> void:
	_clone_counter = 0


# 供调试/报告用
func describe() -> String:
	return "%s%s" % [id, "（克隆体）" if is_clone else ""]
