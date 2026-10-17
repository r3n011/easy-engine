# .ee 项目文件的加载、校验与版本迁移。
#
# 两条关于"后期更新"的硬约束：
#   1. 未知字段一律原样保留。旧版工具打开新版项目、保存后不能把新字段抹掉。
#      实现方式是：我们从不重建字典，只在原字典上读写，所以未知字段天然存活。
#   2. 格式升级走迁移链。加载时把文件当"旧版"读，逐级迁移到当前版本。
extends RefCounted

const Version = preload("res://ee/version.gd")
const MIGRATIONS_DIR := "res://ee/migrations"

var path := ""
var data := {}            # 原始数据（含未知字段）
var problems := []        # [{ level, code, message, where }]
var migrated_from := -1   # 原始 formatVersion；-1 表示无需迁移
var preserved_unknown := 0

func _p(level: String, code: String, message: String, where := "") -> void:
	problems.append({ "level": level, "code": code, "message": message, "where": where if where else path })

func errors() -> Array:
	return problems.filter(func(x): return x["level"] == "error")

func warnings() -> Array:
	return problems.filter(func(x): return x["level"] == "warn")


func load_file(p_path: String) -> bool:
	path = p_path
	var fa := FileAccess.open(p_path, FileAccess.READ)
	if fa == null:
		_p("error", "io", "无法打开项目文件")
		return false
	var text := fa.get_as_text()
	fa.close()
	return load_text(text)


func load_text(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_p("error", "json", "JSON 解析失败")
		return false
	if typeof(parsed) != TYPE_DICTIONARY:
		_p("error", "json", "顶层必须是对象")
		return false
	data = parsed

	var fv: int = int(data.get("formatVersion", 0))
	if fv == 0:
		_p("error", "format_version", "缺少 formatVersion")
		return false

	migrated_from = fv
	var distance := Version.migration_distance(fv)
	if distance > 0:
		if not _migrate(fv):
			return false
	elif distance < 0:
		# 文件来自更新的版本：不猜、不改，只警告。
		# 靠"未知字段保留"让旧版工具不至于破坏新数据。
		_p("warn", "format_newer",
			"项目格式版本 %d 高于本运行时支持的 %d；将按当前版本尽力加载，未知字段会原样保留。" % [fv, Version.FORMAT_VERSION])

	_validate()
	return errors().is_empty()


# ---- 迁移链 -------------------------------------------------------------
# 迁移脚本放在 res://ee/migrations/migrate_<from>_to_<to>.gd，
# 必须提供 static func migrate(data: Dictionary) -> Dictionary。
func _migrate(from_version: int) -> bool:
	var cur := from_version
	while cur < Version.FORMAT_VERSION:
		var next := cur + 1
		var script_path := MIGRATIONS_DIR.path_join("migrate_%d_to_%d.gd" % [cur, next])
		if not ResourceLoader.exists(script_path):
			_p("error", "migration_missing",
				"缺少迁移脚本 %s，无法把格式 %d 升到 %d" % [script_path, cur, next])
			return false
		var script: GDScript = load(script_path)
		if script == null or not script.has_method("migrate"):
			_p("error", "migration_bad", "迁移脚本缺少 static func migrate()：" + script_path)
			return false
		data = script.migrate(data)
		data["formatVersion"] = next
		_p("info", "migrated", "已从格式 %d 迁移到 %d" % [cur, next])
		cur = next
	return true


# ---- 校验 ---------------------------------------------------------------
# 只做"结构层面"的校验，语义层面（积木是否存在等）交给编译器，
# 因为那是依赖注册表的事情。
func _validate() -> void:
	if not data.has("nodes") or typeof(data["nodes"]) != TYPE_ARRAY:
		_p("error", "nodes", "缺少 nodes 数组")
		return

	var seen := {}
	for i in data["nodes"].size():
		var n: Variant = data["nodes"][i]
		var where := "nodes[%d]" % i
		if typeof(n) != TYPE_DICTIONARY:
			_p("error", "node_type", "节点必须是对象", where)
			continue
		var nid: String = n.get("id", "")
		if nid.is_empty():
			_p("error", "node_id", "节点缺少 id", where)
			continue
		if seen.has(nid):
			_p("error", "node_dup", "节点 id 重复：" + nid, where)
		seen[nid] = true
		if not n.has("template"):
			_p("warn", "node_template", "节点 %s 没有 template，将使用默认模板 SPRITE_2D" % nid, where)
		if n.has("scripts") and typeof(n["scripts"]) != TYPE_ARRAY:
			_p("error", "node_scripts", "scripts 必须是数组", where)

	# 舞台
	if not data.has("stage"):
		_p("warn", "stage", "缺少 stage，将使用默认 480x360")


func project_name() -> String:
	return str(data.get("name", "(未命名)"))

func format_version() -> int:
	return int(data.get("formatVersion", 0))

func godot_api_version() -> String:
	return str(data.get("godotApiVersion", Version.GODOT_API_VERSION))

func declared_extensions() -> Array:
	return data.get("extensions", [])

func nodes() -> Array:
	return data.get("nodes", [])


# 保存時把原始字典（含未知字段）写回，并刷新元信息。
# 注意：这是"往返不丢数据"的关键——我们从不重建字典。
func save_string(generator_name: String, generator_version: String) -> String:
	var out := data.duplicate(true)
	out["formatVersion"] = Version.FORMAT_VERSION
	out["generator"] = { "name": generator_name, "version": generator_version }
	out["godotApiVersion"] = Version.GODOT_API_VERSION
	return JSON.stringify(out, "  ", false)


# 统计有多少个顶层字段是本运行时"不认识"的（用于给用户提示，不用于删改）。
func count_unknown_top_level(known: Array) -> int:
	var n := 0
	for k in data:
		if not known.has(k):
			n += 1
	return n
