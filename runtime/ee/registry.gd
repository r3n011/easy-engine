# 注册表：把 defs/ 目录下的 JSON 定义读成"积木表"和"op 表"。
#
# 扩展性设计：
#   * 文件名前缀决定类别：blocks.<扩展id>.json / ops.<扩展id>.json
#   * 新增积木 = 新增一个 JSON 文件，不改引擎代码
#   * 编辑器与运行时共用同一份定义（编辑器据此生成 Blockly 积木）
#   * op 表与积木表分离：运行时只认 op，所以扩展可以自由设计积木外观
extends RefCounted

const Version = preload("res://ee/version.gd")

# id -> 定义
var blocks := {}
# id -> 定义
var ops := {}
# id -> { id, version, name, color, categories: [], blocks: [] }
var extensions := {}
# 有序分类列表（编辑器按此顺序摆放）
var categories := []
# 加载过程中的问题： [{ level, code, message, where }]
var problems := []

func _add_problem(level: String, code: String, message: String, where: String) -> void:
	problems.append({ "level": level, "code": code, "message": message, "where": where })

func errors() -> Array:
	return problems.filter(func(p): return p["level"] == "error")

func warnings() -> Array:
	return problems.filter(func(p): return p["level"] == "warn")


# 扫描目录并加载全部定义。
# only_extensions 非空时，只加载核心 + 列出的扩展（其余仍会被登记，但标记为未启用）。
func load_defs(dir_path: String, enabled_extensions: Array = []) -> void:
	blocks.clear()
	ops.clear()
	extensions.clear()
	categories.clear()
	problems.clear()

	var dir := DirAccess.open(dir_path)
	if dir == null:
		_add_problem("error", "defs_dir_missing", "找不到定义目录：" + dir_path, dir_path)
		return

	var files := dir.get_files()
	files.sort()  # 保证加载顺序稳定，回归可比

	for f in files:
		if not f.ends_with(".json"):
			continue
		if f.begins_with("blocks."):
			_load_block_file(dir_path.path_join(f), enabled_extensions)
		elif f.begins_with("ops."):
			_load_op_file(dir_path.path_join(f), enabled_extensions)

	_validate_cross_references()


func _read_json(path: String) -> Variant:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		_add_problem("error", "io", "无法打开文件", path)
		return null
	var text := fa.get_as_text()
	fa.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_add_problem("error", "json", "JSON 解析失败", path)
		return null
	if typeof(parsed) != TYPE_DICTIONARY:
		_add_problem("error", "json", "顶层必须是对象", path)
		return null
	return parsed


func _register_extension(data: Dictionary, path: String) -> void:
	var ext_id: String = data.get("extension", "")
	if ext_id.is_empty():
		_add_problem("error", "ext_id", "缺少 extension 字段", path)
		return
	if extensions.has(ext_id):
		return
	extensions[ext_id] = {
		"id": ext_id,
		"version": int(data.get("extensionVersion", 1)),
		"requires": data.get("requires", []),
		"description": data.get("description", ""),
		"blocks": [],
		"ops": [],
	}


func _load_block_file(path: String, enabled: Array) -> void:
	var data: Variant = _read_json(path)
	if data == null:
		return
	_register_extension(data, path)
	var ext_id: String = data.get("extension", "")

	for cat in data.get("categories", []):
		categories.append({
			"id": cat.get("id", ""),
			"name": cat.get("name", cat.get("id", "")),
			"color": cat.get("color", "#888888"),
			"extension": ext_id,
		})

	for b in data.get("blocks", []):
		var bid: String = b.get("id", "")
		if bid.is_empty():
			_add_problem("error", "block_id", "积木缺少 id", path)
			continue
		if blocks.has(bid):
			_add_problem("warn", "block_dup", "积木 id 重复，后一个被忽略：" + bid, path)
			continue
		var def: Dictionary = b.duplicate(true)
		def["extension"] = ext_id
		def["enabled"] = enabled.is_empty() or enabled.has(ext_id)
		blocks[bid] = def
		extensions[ext_id]["blocks"].append(bid)


func _load_op_file(path: String, enabled: Array) -> void:
	var data: Variant = _read_json(path)
	if data == null:
		return
	_register_extension(data, path)
	var ext_id: String = data.get("extension", "")
	# 文件头的 provider 要下发到每一条 op，运行时据此找到实现
	var provider: String = str(data.get("provider", ""))

	for o in data.get("ops", []):
		var oid: String = o.get("id", "")
		if oid.is_empty():
			_add_problem("error", "op_id", "op 缺少 id", path)
			continue
		if ops.has(oid):
			_add_problem("warn", "op_dup", "op id 重复，后一个被忽略：" + oid, path)
			continue
		var def: Dictionary = o.duplicate(true)
		def["extension"] = ext_id
		def["provider"] = provider
		def["enabled"] = enabled.is_empty() or enabled.has(ext_id)
		ops[oid] = def
		extensions[ext_id]["ops"].append(oid)
	if not provider.is_empty():
		extensions[ext_id]["provider"] = provider


# 交叉校验：积木的 ir 模板里引用到的每个 op，都必须存在于 op 表。
# 这一步能在编译期就拦住拼错的扩展，而不是等运行时报错。
func _validate_cross_references() -> void:
	for bid in blocks:
		var def: Dictionary = blocks[bid]
		for oid in collect_ops_in_template(def.get("ir", {})):
			if not ops.has(oid):
				var ext: String = def.get("extension", "?")
				_add_problem("error", "op_unknown",
					"积木 %s（扩展 %s）引用了不存在的 op：%s" % [bid, ext, oid], bid)

	for eid in extensions:
		for req in extensions[eid].get("requires", []):
			var rid: String = req.get("id", "")
			var rver: String = req.get("version", "")
			if not extensions.has(rid):
				_add_problem("error", "ext_missing",
					"扩展 %s 依赖 %s，但它没有被加载" % [eid, rid], eid)
			elif not Version.satisfies(int(extensions[rid]["version"]), rver):
				_add_problem("error", "ext_version",
					"扩展 %s 需要 %s %s，实际是 %d" % [eid, rid, rver, int(extensions[rid]["version"])], eid)


# 从一个 ir 模板里收集所有 op 名（递归）。
static func collect_ops_in_template(node: Variant, out: Array = []) -> Array:
	if typeof(node) == TYPE_DICTIONARY:
		if node.has("op") and typeof(node["op"]) == TYPE_STRING:
			out.append(node["op"])
		for k in node:
			if k == "op":
				continue
			collect_ops_in_template(node[k], out)
	elif typeof(node) == TYPE_ARRAY:
		for v in node:
			collect_ops_in_template(v, out)
	return out


func has_block(id: String) -> bool:
	return blocks.has(id)

func has_op(id: String) -> bool:
	return ops.has(id)

func get_block(id: String) -> Dictionary:
	return blocks.get(id, {})

func op_yields(id: String) -> bool:
	return bool(ops.get(id, {}).get("yields", false))

func op_is_pure(id: String) -> bool:
	return bool(ops.get(id, {}).get("pure", false))

# 某个扩展是否被启用
func is_ext_enabled(ext_id: String) -> bool:
	if not extensions.has(ext_id):
		return false
	var e: Dictionary = extensions[ext_id]
	for bid in e["blocks"]:
		return bool(blocks[bid].get("enabled", true))
	return true


func summary() -> String:
	var s := "扩展 %d 个，积木 %d 个，op %d 个，分类 %d 个" % [
		extensions.size(), blocks.size(), ops.size(), categories.size()]
	s += "；错误 %d，警告 %d" % [errors().size(), warnings().size()]
	return s
