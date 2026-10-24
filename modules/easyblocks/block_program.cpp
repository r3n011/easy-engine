/**************************************************************************/
/*  block_program.cpp                                                     */
/**************************************************************************/

#include "block_program.h"

#include "block_library.h"

#include "core/io/json.h"
#include "core/object/class_db.h"

void BlockProgram::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_scripts", "scripts"), &BlockProgram::set_scripts);
	ClassDB::bind_method(D_METHOD("get_scripts"), &BlockProgram::get_scripts);
	ClassDB::bind_method(D_METHOD("set_scripts_json", "json"), &BlockProgram::set_scripts_json);
	ClassDB::bind_method(D_METHOD("get_scripts_json"), &BlockProgram::get_scripts_json);
	ClassDB::bind_method(D_METHOD("get_ir"), &BlockProgram::get_ir);
	ClassDB::bind_method(D_METHOD("get_errors"), &BlockProgram::get_errors);
	ClassDB::bind_method(D_METHOD("is_compiled"), &BlockProgram::is_compiled);
	ClassDB::bind_method(D_METHOD("compile"), &BlockProgram::compile);

	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "scripts", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
			"set_scripts", "get_scripts");
}

void BlockProgram::set_scripts(const Array &p_scripts) {
	scripts = p_scripts;
	compiled = false;
}

Array BlockProgram::get_scripts() const {
	return scripts;
}

Error BlockProgram::set_scripts_json(const String &p_json) {
	JSON json;
	Error err = json.parse(p_json);
	if (err != OK) {
		_error(String::utf8("JSON 解析失败：") + json.get_error_message(), "");
		return err;
	}
	Variant data = json.get_data();
	if (data.get_type() == Variant::ARRAY) {
		set_scripts(data);
		return OK;
	}
	if (data.get_type() == Variant::DICTIONARY) {
		Dictionary d = data;
		if (d.has("scripts")) {
			set_scripts(d["scripts"]);
			return OK;
		}
	}
	_error(String::utf8("JSON 里没有 scripts 数组"), "");
	return ERR_INVALID_DATA;
}

String BlockProgram::get_scripts_json() const {
	return JSON::stringify(scripts, "", false, true);
}

Array BlockProgram::get_ir() const {
	return ir;
}

Array BlockProgram::get_errors() const {
	return errors;
}

bool BlockProgram::is_compiled() const {
	return compiled;
}

void BlockProgram::_error(const String &p_msg, const String &p_where) {
	Dictionary e;
	e["message"] = p_msg;
	e["where"] = p_where;
	errors.push_back(e);
}

Error BlockProgram::compile() {
	ir.clear();
	errors.clear();

	BlockLibrary *lib = BlockLibrary::get_singleton();
	lib->load_builtin();

	for (int i = 0; i < scripts.size(); i++) {
		Dictionary s = scripts[i];
		if (s.is_empty()) {
			continue;
		}
		Dictionary top = s.get("top", Dictionary());
		if (top.is_empty()) {
			continue;
		}
		Dictionary op = _compile_block(top, 0);
		if (!op.is_empty()) {
			ir.push_back(op);
		}
	}

	compiled = true;
	return errors.is_empty() ? OK : ERR_PARSE_ERROR;
}

Dictionary BlockProgram::_compile_block(const Dictionary &p_block, int p_depth) {
	if (p_depth > 64) {
		_error(String::utf8("积木嵌套过深（>64 层）"), String(p_block.get("block", String())));
		return Dictionary();
	}

	const String id = p_block.get("block", String());
	if (id.is_empty()) {
		_error(String::utf8("积木缺少 block 字段"), "");
		return Dictionary();
	}

	BlockLibrary *lib = BlockLibrary::get_singleton();
	if (!lib->has_block(id)) {
		_error(String::utf8("未知积木：") + id, id);
		return Dictionary();
	}

	Dictionary def = lib->find_block(id);
	Dictionary tmpl = def.get("ir", Dictionary());
	Dictionary inputs = p_block.get("inputs", Dictionary());

	Dictionary op = _instantiate(tmpl, def, inputs, p_depth);
	if (!op.is_empty()) {
		// target 注入：op 声明了 target 参数、而积木没写死时，用积木定义里的
		const String op_id = op.get("op", String());
		if (lib->has_op(op_id)) {
			Dictionary op_def = lib->find_op(op_id);
			Array args = op_def.get("args", Array());
			// 注意：_instantiate 会先把声明的参数补成 null，所以这里不能只看 has()，
			// 还要看值是不是空——否则 target 永远注入不进去（这个坑 GDScript 版也踩过一次）。
			if (args.has("target") && (!op.has("target") || op["target"].get_type() == Variant::NIL)) {
				op["target"] = def.get("target", Variant("@self"));
			}
		}
	}
	return op;
}

Dictionary BlockProgram::_instantiate(const Variant &p_template, const Dictionary &p_def, const Dictionary &p_inputs, int p_depth) {
	if (p_template.get_type() != Variant::DICTIONARY) {
		return Dictionary();
	}
	Dictionary tmpl = p_template;

	// 整块模板就是String::utf8("取一个参数")的情况
	if (tmpl.has("$arg")) {
		Variant v = _resolve_value(tmpl["$arg"], p_def, p_inputs, p_depth);
		return v.get_type() == Variant::DICTIONARY ? Dictionary(v) : Dictionary();
	}

	BlockLibrary *lib = BlockLibrary::get_singleton();
	Dictionary out;
	Array keys = tmpl.keys();

	for (int i = 0; i < keys.size(); i++) {
		const String key = keys[i];
		Variant v = tmpl[key];

		if (v.get_type() == Variant::DICTIONARY) {
			Dictionary d = v;
			if (d.has("$arg")) {
				out[key] = _resolve_value(d["$arg"], p_def, p_inputs, p_depth);
			} else if (d.has("$branch")) {
				out[key] = _resolve_branch(d["$branch"], p_inputs, p_depth);
			} else {
				out[key] = _instantiate(d, p_def, p_inputs, p_depth);
			}
		} else if (v.get_type() == Variant::ARRAY) {
			Array src = v;
			Array dst;
			for (int j = 0; j < src.size(); j++) {
				Variant item = src[j];
				if (item.get_type() == Variant::DICTIONARY) {
					Dictionary di = item;
					if (di.has("$arg")) {
						dst.push_back(_resolve_value(di["$arg"], p_def, p_inputs, p_depth));
					} else if (di.has("$branch")) {
						dst.push_back(_resolve_branch(di["$branch"], p_inputs, p_depth));
					} else {
						dst.push_back(_instantiate(di, p_def, p_inputs, p_depth));
					}
				} else {
					dst.push_back(item);
				}
			}
			out[key] = dst;
		} else {
			out[key] = v;
		}
	}

	// 补上 op 声明的默认值（默认值写在 op 定义里，不硬编码在编译器里）
	const String op_id = out.get("op", String());
	if (!op_id.is_empty() && lib->has_op(op_id)) {
		Dictionary op_def = lib->find_op(op_id);
		Dictionary defaults = op_def.get("defaults", Dictionary());
		Array args = op_def.get("args", Array());
		for (int i = 0; i < args.size(); i++) {
			const String a = args[i];
			if (!out.has(a) || out[a].get_type() == Variant::NIL) {
				if (defaults.has(a)) {
					out[a] = defaults[a];
				} else if (!out.has(a)) {
					out[a] = Variant();
				}
			}
		}
	}
	return out;
}

Variant BlockProgram::_resolve_value(const String &p_name, const Dictionary &p_def, const Dictionary &p_inputs, int p_depth) {
	if (!p_inputs.has(p_name)) {
		Dictionary args = p_def.get("args", Dictionary());
		if (args.has(p_name)) {
			Dictionary spec = args[p_name];
			return spec.get("default", Variant());
		}
		return Variant();
	}

	Variant box = p_inputs[p_name];
	if (box.get_type() != Variant::DICTIONARY) {
		return box;
	}
	Dictionary b = box;
	if (!b.has("value")) {
		return Variant();
	}

	Variant v = b["value"];
	if (v.get_type() == Variant::DICTIONARY) {
		Dictionary d = v;
		if (d.has("block")) {
			return _compile_block(d, p_depth + 1);
		}
	}
	return v;
}

Array BlockProgram::_resolve_branch(const String &p_name, const Dictionary &p_inputs, int p_depth) {
	Array out;
	if (!p_inputs.has(p_name)) {
		return out;
	}
	Variant box = p_inputs[p_name];
	if (box.get_type() != Variant::DICTIONARY) {
		return out;
	}
	Dictionary b = box;
	if (!b.has("stack")) {
		return out;
	}

	Variant cur = b["stack"];
	int guard = 0;
	while (cur.get_type() == Variant::DICTIONARY) {
		Dictionary d = cur;
		if (d.is_empty()) {
			break;
		}
		if (++guard > 100000) {
			_error(String::utf8("积木串疑似循环引用"), p_name);
			break;
		}
		Dictionary op = _compile_block(d, p_depth + 1);
		if (!op.is_empty()) {
			out.push_back(op);
		}
		cur = d.get("next", Dictionary());
	}
	return out;
}

BlockProgram::BlockProgram() {
}
