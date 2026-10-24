/**************************************************************************/
/*  block_program.h                                                       */
/*  Easy Engine —— 积木程序（Resource）                                     */
/**************************************************************************/

#pragma once

#include "core/io/resource.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

/**
 * 一份积木程序：存String::utf8("积木脚本")，编译成"IR"。
 *
 * 它是一个 **Resource**，所以能：
 *   · 存进 .tres / .tscn，跟着场景走
 *   · 在检查器里选中、被其他节点引用
 *   · 作为引擎资产被导出
 *
 * 这正是String::utf8("积木是引擎一等公民")的关键：它不是我们自造的文件格式，
 * 而是 Godot 自己的资源体系里的一员。
 */
class BlockProgram : public Resource {
	GDCLASS(BlockProgram, Resource);

	Array scripts; // 积木脚本：Array<{ top: <积木节点> }>
	Array ir; // 编译产物
	Array errors; // Array<{ message, where }>
	bool compiled = false;

	Dictionary _compile_block(const Dictionary &p_block, int p_depth);
	Dictionary _instantiate(const Variant &p_template, const Dictionary &p_def, const Dictionary &p_inputs, int p_depth);
	Variant _resolve_value(const String &p_name, const Dictionary &p_def, const Dictionary &p_inputs, int p_depth);
	Array _resolve_branch(const String &p_name, const Dictionary &p_inputs, int p_depth);
	void _error(const String &p_msg, const String &p_where);

protected:
	static void _bind_methods();

public:
	void set_scripts(const Array &p_scripts);
	Array get_scripts() const;

	/** 从 JSON 文本设置积木脚本（便于先用文本写程序，等编辑器做出来）。 */
	Error set_scripts_json(const String &p_json);
	String get_scripts_json() const;

	Array get_ir() const;
	Array get_errors() const;
	bool is_compiled() const;

	/** 编译成 IR。失败时 errors 里会有可读信息。 */
	Error compile();

	BlockProgram();
};
