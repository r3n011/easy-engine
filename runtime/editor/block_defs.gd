# 积木定义 → 积木外观。
#
# 整个编辑器是"数据驱动"的：积木长什么样、有哪些槽位，全部来自
# runtime/ee/defs/blocks.*.json —— 与运行时共用同一份定义，
# 所以新增积木只要改一个 JSON，编辑器和运行时同时得到它。
#
# 这一段是纯逻辑（不涉及绘制），把 message 拆成有序的"段"：
#   {kind:"text",  text}                        普通文字
#   {kind:"field", name, ftype, options, value} 可编辑字段（下拉/文本/数字）
#   {kind:"value", name, vtype}                 值槽（可以塞进一个报告积木）
#   {kind:"stmt",  name}                        语句槽（可以叠一串积木）
extends RefCounted

const DEFS_DIR := "res://ee/defs"

var blocks := {}        # id -> {id, category, color, shape, segments, target, ...}
var categories := []    # [{id, name, color}]
var extensions := []


func load_defs(enabled: Array = []) -> void:
	blocks.clear()
	categories.clear()
	var dir := DirAccess.open(DEFS_DIR)
	if dir == null:
		push_error("找不到积木定义目录 " + DEFS_DIR)
		return

	var files := dir.get_files()
	files.sort()
	for f in files:
		if f.begins_with("blocks.") and f.ends_with(".json"):
			_load_file(DEFS_DIR.path_join(f), enabled)
	# 只有核心必须存在，扩展缺失不算错
	if blocks.is_empty():
		push_error("没有加载到任何积木定义")


func _load_file(path: String, enabled: Array) -> void:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return
	var data: Variant = JSON.parse_string(fa.get_as_text())
	fa.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("积木定义解析失败：" + path)
		return

	var ext := str(data.get("extension", ""))
	if not enabled.is_empty() and ext != "ee.core" and not enabled.has(ext):
		return
	extensions.append({ "id": ext, "version": int(data.get("extensionVersion", 1)) })

	for c in data.get("categories", []):
		categories.append({
			"id": str(c.get("id", "")),
			"name": str(c.get("name", "")),
			"color": str(c.get("color", "#888888")),
			"extension": ext,
		})

	for b in data.get("blocks", []):
		var id := str(b.get("id", ""))
		if id.is_empty():
			continue
		var cat := str(b.get("category", ""))
		blocks[id] = {
			"id": id,
			"extension": ext,
			"category": cat,
			"color": _category_color(cat),
			"shape": str(b.get("shape", "stack")),
			"target": str(b.get("target", "")),
			"segments": _parse_message(b),
			"raw": b,
		}


func _category_color(cat: String) -> Color:
	for c in categories:
		if c["id"] == cat:
			return Color.html(c["color"])
	return Color.html("#888888")


# 把 message 里的 {NAME} 拆成段；声明了却没写进 message 的分支补在末尾
# （例如「当 ▶ 被点击」的 BODY —— 它不写在文字里，但要有个语句槽）
func _parse_message(b: Dictionary) -> Array:
	var msg := str(b.get("message", ""))
	var args: Dictionary = b.get("args", {})
	var branch_names := []
	for br in b.get("branches", []):
		branch_names.append(str(br.get("name", "")))

	var segs := []
	var seen := {}
	var re := RegEx.new()
	re.compile("\\{(\\w+)\\}")
	var last := 0
	for m in re.search_all(msg):
		var text := msg.substr(last, m.get_start() - last)
		if not text.is_empty():
			segs.append({ "kind": "text", "text": text })
		var name := m.get_string(1)
		seen[name] = true
		segs.append(_segment_for(name, args, branch_names))
		last = m.get_end()
	var tail := msg.substr(last)
	if not tail.is_empty():
		segs.append({ "kind": "text", "text": tail })

	for name in branch_names:
		if not seen.has(name):
			segs.append({ "kind": "stmt", "name": name })

	if segs.is_empty():
		segs.append({ "kind": "text", "text": "(无文字)" })
	return segs


func _segment_for(name: String, args: Dictionary, branch_names: Array) -> Dictionary:
	if branch_names.has(name):
		return { "kind": "stmt", "name": name }
	var spec: Dictionary = args.get(name, {})
	var t := str(spec.get("type", "any"))
	match t:
		"dropdown":
			return {
				"kind": "field", "name": name, "ftype": "dropdown",
				"options": spec.get("options", []), "value": spec.get("default", ""),
			}
		"variable", "list", "costume", "sound", "property", "method", "signal":
			return {
				"kind": "field", "name": name, "ftype": "text",
				"value": spec.get("default", ""), "wide": true,
			}
		"number":
			return { "kind": "value", "name": name, "vtype": "number", "value": spec.get("default", 0) }
		"boolean":
			return { "kind": "value", "name": name, "vtype": "boolean", "value": spec.get("default", false) }
		"expression", "code":
			return { "kind": "value", "name": name, "vtype": t, "value": spec.get("default", "") }
		_:
			return { "kind": "value", "name": name, "vtype": "any", "value": spec.get("default", "") }


# ---- 查询 ---------------------------------------------------------------

func block_ids() -> Array:
	var out := blocks.keys()
	out.sort()
	return out

func by_category(cat: String) -> Array:
	var out := []
	for id in block_ids():
		if blocks[id]["category"] == cat:
			out.append(id)
	return out

func category_name(cat: String) -> String:
	for c in categories:
		if c["id"] == cat:
			return c["name"]
	return cat

func def(id: String) -> Dictionary:
	return blocks.get(id, {})
