# 编译器：把 .ee 里的积木脚本编译成 IR。
#
# 设计要点（都是为了"IR 可以演进而不破坏老项目"）：
#   * .ee 里只出现积木 id，不出现 opcode。opcode 由积木定义映射出来。
#     这样以后改 IR、拆 op、合 op，老项目一行都不用动。
#   * 编译期做交叉校验：积木是否存在、所属扩展是否启用、op 是否已注册。
#     报错要带上"你需要哪个扩展"，而不是一句 "unknown op"。
#   * 输出稳定：键排序后序列化，方便做回归比对。
extends RefCounted

const Version = preload("res://ee/version.gd")

var registry
var problems := []

var _target_index := {}   # 节点 id -> 节点字典

func _p(level: String, code: String, message: String, where := "") -> void:
	problems.append({ "level": level, "code": code, "message": message, "where": where })

func errors() -> Array:
	return problems.filter(func(x): return x["level"] == "error")

func warnings() -> Array:
	return problems.filter(func(x): return x["level"] == "warn")


func compile(project) -> Dictionary:
	var data: Dictionary = project.data
	problems.clear()
	_target_index.clear()

	for n in project.nodes():
		_target_index[str(n.get("id", ""))] = n

	var out := {
		"irVersion": Version.IR_VERSION,
		"compilerVersion": Version.COMPILER_VERSION,
		"sourceFormatVersion": project.format_version(),
		"godotApiVersion": project.godot_api_version(),
		"name": project.project_name(),
		"stage": _compile_stage(data.get("stage", {})),
		"globals": _compile_globals(data.get("globals", {})),
		"extensions": _used_extensions(project),
		"nodes": [],
	}

	for n in project.nodes():
		out["nodes"].append(_compile_node(n))

	return out


func _compile_stage(stage: Dictionary) -> Dictionary:
	var size: Array = stage.get("size", [480, 360])
	return {
		"size": [int(size[0]), int(size[1])],
		"background": stage.get("background", null),
		"settings": stage.get("settings", {}),
	}


func _compile_globals(g: Dictionary) -> Dictionary:
	return {
		"variables": g.get("variables", []),
		"lists": g.get("lists", []),
	}


# 项目的扩展依赖 = .ee 里声明的 + 实际用到的积木所属扩展
func _used_extensions(project) -> Array:
	var used := {}
	for n in project.nodes():
		for s in n.get("scripts", []):
			_collect_extensions(s.get("top", {}), used)
	var out: Array = []
	for e in project.declared_extensions():
		out.append(e)
	for eid in used:
		var found := false
		for e in out:
			if str(e.get("id", "")) == eid:
				found = true
		if not found and eid != "ee.core":
			out.append({ "id": eid, "version": ">=1" })
	return out


func _collect_extensions(block_obj: Variant, out: Dictionary) -> void:
	if typeof(block_obj) != TYPE_DICTIONARY or block_obj.is_empty():
		return
	var bid: String = block_obj.get("block", "")
	if registry.has_block(bid):
		out[str(registry.get_block(bid).get("extension", "ee.core"))] = true
	for k in block_obj.get("inputs", {}):
		var inp: Variant = block_obj["inputs"][k]
		if typeof(inp) == TYPE_DICTIONARY:
			if inp.has("stack"):
				_collect_extensions(inp["stack"], out)
			if inp.has("value") and typeof(inp["value"]) == TYPE_DICTIONARY:
				if inp["value"].has("block"):
					_collect_extensions(inp["value"], out)
	_collect_extensions(block_obj.get("next", {}), out)


func _compile_node(n: Dictionary) -> Dictionary:
	var nid: String = str(n.get("id", ""))
	var scripts: Array = []
	var idx := 0
	for s in n.get("scripts", []):
		var where := "节点 %s 的脚本 #%d" % [nid, idx]
		idx += 1
		var top: Variant = s.get("top", {})
		if typeof(top) != TYPE_DICTIONARY or top.is_empty():
			_p("warn", "script_empty", "脚本为空，已跳过", where)
			continue
		var op := _compile_block(top, where)
		if op.is_empty():
			continue
		var shape := ""
		if registry.has_block(str(top.get("block", ""))):
			shape = str(registry.get_block(top.get("block", "")).get("shape", ""))
		if shape != "hat":
			_p("warn", "script_no_hat",
				"脚本的第 1 个积木不是帽子积木（%s），它不会被自动触发，只能被别的脚本调用。" % shape,
				where)
		scripts.append(op)

	return {
		"id": nid,
		"name": n.get("name", nid),
		"template": n.get("template", "SPRITE_2D"),
		"parent": n.get("parent", "@stage"),
		"order": int(n.get("order", 0)),
		"transform": n.get("transform", {}),
		"visible": bool(n.get("visible", true)),
		"costumes": n.get("costumes", []),
		"sounds": n.get("sounds", []),
		"localVariables": n.get("localVariables", []),
		"scripts": scripts,
	}


# ---- 编译一个积木 -------------------------------------------------------
func _compile_block(block_obj: Dictionary, where: String) -> Dictionary:
	var bid: String = str(block_obj.get("block", ""))
	if bid.is_empty():
		_p("error", "block_missing_id", "积木缺少 block 字段", where)
		return {}
	if not registry.has_block(bid):
		_p("error", "block_unknown",
			"未知积木 %s。若它来自第三方扩展，请用 --ext <扩展id> 启用。" % bid, where)
		return {}

	var def: Dictionary = registry.get_block(bid)
	if not bool(def.get("enabled", true)):
		_p("error", "block_ext_disabled",
			"积木 %s 来自扩展 %s，当前未启用。请用 --ext %s 启用。"
				% [bid, def.get("extension", "?"), def.get("extension", "?")], where)
		return {}

	var inputs: Dictionary = block_obj.get("inputs", {})
	var op: Dictionary = _instantiate(def.get("ir", {}), def, inputs, where)

	# target 注入：op 声明了 target 参数，而模板没写死时，用积木上的 target
	if _op_wants_arg(def.get("ir", {}), "target") and op.get("target") == null:
		op["target"] = str(def.get("target", "@self"))
	return op


func _op_wants_arg(template: Variant, arg_name: String) -> bool:
	if typeof(template) != TYPE_DICTIONARY:
		return false
	if not template.has("op"):
		return false
	var oid: String = str(template["op"])
	if not registry.has_op(oid):
		return false
	for a in registry.ops[oid].get("args", []):
		if str(a) == arg_name:
			return true
	return false


# 把积木定义里的 ir 模板实例化成真正的 op
func _instantiate(template: Variant, def: Dictionary, inputs: Dictionary, where: String) -> Dictionary:
	if typeof(template) != TYPE_DICTIONARY:
		return {}

	var out := {}
	for k in template:
		var v: Variant = template[k]

		if k == "$arg":
			out = _as_op(_resolve_value(str(v), def, inputs, where))
			continue
		if k == "$branch":
			out = _as_op(_resolve_branch(str(v), inputs, where))
			continue

		if typeof(v) == TYPE_DICTIONARY:
			if v.has("$arg"):
				out[k] = _resolve_value(str(v["$arg"]), def, inputs, where)
			elif v.has("$branch"):
				out[k] = _resolve_branch(str(v["$branch"]), inputs, where)
			else:
				out[k] = _instantiate(v, def, inputs, where)
		elif typeof(v) == TYPE_ARRAY:
			var arr: Array = []
			for item in v:
				if typeof(item) == TYPE_DICTIONARY and (item.has("$arg") or item.has("$branch")):
					if item.has("$arg"):
						arr.append(_resolve_value(str(item["$arg"]), def, inputs, where))
					else:
						arr.append(_resolve_branch(str(item["$branch"]), inputs, where))
				else:
					arr.append(_instantiate(item, def, inputs, where))
			out[k] = arr
		else:
			out[k] = v

	# op 声明的参数若模板没给，按 op 定义里的 defaults 补，再不行补 null。
	# 默认值来自数据（op 定义），不是硬编码在这里——扩展也能给自己的 op 加默认值。
	var oid: String = str(out.get("op", ""))
	if registry.has_op(oid):
		var op_def: Dictionary = registry.ops[oid]
		var defaults: Dictionary = op_def.get("defaults", {})
		for a in op_def.get("args", []):
			if not out.has(a) or out[a] == null:
				if defaults.has(a):
					out[a] = defaults[a]
				elif not out.has(a):
					out[a] = null
	return out


func _as_op(v: Variant) -> Dictionary:
	if typeof(v) == TYPE_DICTIONARY:
		return v
	return {}


# 取一个值输入：可以是字面量，也可以是嵌套的积木
func _resolve_value(arg_name: String, def: Dictionary, inputs: Dictionary, where: String) -> Variant:
	var declared: Dictionary = def.get("args", {}).get(arg_name, {})
	if not inputs.has(arg_name):
		if declared.has("default"):
			return declared["default"]
		_p("warn", "input_missing", "积木 %s 缺少输入 %s，使用默认值" % [def.get("id", "?"), arg_name], where)
		return null

	var box: Variant = inputs[arg_name]
	if typeof(box) != TYPE_DICTIONARY:
		return box
	if not box.has("value"):
		_p("warn", "input_shape", "输入 %s 缺少 value，已忽略" % arg_name, where)
		return null

	var v: Variant = box["value"]
	if typeof(v) == TYPE_DICTIONARY and v.has("block"):
		var sub := _compile_block(v, "%s / 输入 %s" % [where, arg_name])
		return sub
	return v


# 取一个分支（语句块）输入，编译成 op 数组
func _resolve_branch(branch_name: String, inputs: Dictionary, where: String) -> Array:
	var ops: Array = []
	if not inputs.has(branch_name):
		return ops
	var box: Variant = inputs[branch_name]
	if typeof(box) != TYPE_DICTIONARY or not box.has("stack"):
		_p("warn", "branch_shape", "分支 %s 缺少 stack，按空处理" % branch_name, where)
		return ops
	var cur: Variant = box["stack"]
	var guard := 0
	while typeof(cur) == TYPE_DICTIONARY and not cur.is_empty():
		guard += 1
		if guard > 100000:
			_p("error", "branch_cycle", "分支 %s 疑似存在循环引用" % branch_name, where)
			break
		var op := _compile_block(cur, where)
		if not op.is_empty():
			ops.append(op)
		cur = cur.get("next", {})
	return ops
