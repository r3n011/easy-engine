# 积木画布 ⇄ 我们的积木脚本格式 的双向转换。
#
# 与 docs/format/SYNC.md §6 一致：**画布是视图，不是数据。**
# 项目文件里存的是积木脚本（{block, inputs, next}），不是编辑器内部结构。
# 好处：编辑器换掉、积木渲染改样，已有项目都不受影响。
extends RefCounted

var canvas   # BlockCanvas

func setup(p_canvas) -> void:
	canvas = p_canvas


# ============================================================ 导出：画布 → 脚本

func to_scripts() -> Array:
	var out := []
	for r in canvas.roots:
		if not is_instance_valid(r):
			continue
		out.append({ "top": block_to_script(r) })
	return out


func block_to_script(b) -> Dictionary:
	var inputs := {}
	for seg in b.def.get("segments", []):
		var kind := str(seg.get("kind", ""))
		if kind != "field" and kind != "value" and kind != "stmt":
			continue   # 文本段没有名字，跳过
		var name := str(seg.get("name", ""))
		if name.is_empty():
			continue
		match kind:
			"field", "value":
				if b.inputs.has(name):
					inputs[name] = { "value": block_to_script(b.inputs[name]) }
				else:
					inputs[name] = { "value": b.fields.get(name) }
			"stmt":
				var list: Array = b.stmt_slots.get(name, [])
				inputs[name] = { "stack": block_to_script(list[0]) if not list.is_empty() else {} }
	var out := { "block": b.block_id, "inputs": inputs }
	if b.next_block != null:
		out["next"] = block_to_script(b.next_block)
	return out


# ============================================================ 导入：脚本 → 画布

func from_scripts(scripts: Array, origin := Vector2(28, 24)) -> void:
	canvas.clear_all()
	var y := origin.y
	for s in scripts:
		if typeof(s) != TYPE_DICTIONARY or not s.has("top"):
			continue
		var top: Dictionary = s["top"]
		if top.is_empty():
			continue
		var b = build_block(top)
		if b == null:
			continue
		canvas.add_top(b, Vector2(origin.x, y))
		b.relayout()
		y += b.total_stack_height() + 30.0
	canvas.relayout_all()


func build_block(node: Dictionary):
	var id := str(node.get("block", ""))
	var b = canvas.instantiate(id)
	if b == null:
		return null
	var inputs: Dictionary = node.get("inputs", {})
	for seg in b.def.get("segments", []):
		var kind := str(seg.get("kind", ""))
		if kind != "field" and kind != "value" and kind != "stmt":
			continue   # 文本段没有名字
		var name := str(seg.get("name", ""))
		if name.is_empty() or not inputs.has(name):
			continue
		var box: Variant = inputs[name]
		if typeof(box) != TYPE_DICTIONARY:
			b.fields[name] = box
			continue
		if box.has("stack"):
			var s: Variant = box["stack"]
			if typeof(s) == TYPE_DICTIONARY and not s.is_empty():
				var child = build_block(s)
				if child != null:
					canvas.attach_stmt(b, name, child)
		elif box.has("value"):
			var v: Variant = box["value"]
			if typeof(v) == TYPE_DICTIONARY and v.has("block"):
				var r = build_block(v)
				if r != null:
					canvas.attach_value(b, name, r)
			else:
				b.fields[name] = v
	if node.has("next"):
		var nxt = build_block(node["next"])
		if nxt != null:
			canvas.attach_next(b, nxt)
	return b
