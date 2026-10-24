/**************************************************************************/
/*  block_library.h                                                       */
/*  Easy Engine —— 积木定义注册表                                          */
/**************************************************************************/

#pragma once

#include "core/object/object.h"
#include "core/templates/hash_map.h"
#include "core/variant/dictionary.h"

/**
 * 积木与 op 的定义表。
 *
 * 定义来自 defs/*.json，在构建时被打包进二进制（block_defs.gen.h）。
 * 运行时和编辑器都从这里拿定义 —— 所以String::utf8("新增积木")永远只改一个 JSON。
 */
class BlockLibrary : public Object {
	GDCLASS(BlockLibrary, Object);

	static BlockLibrary *singleton;

	bool loaded = false;
	HashMap<String, Dictionary> blocks;
	HashMap<String, Dictionary> ops;
	Vector<Dictionary> categories;
	Vector<Dictionary> extensions;
	Vector<String> block_order; // 保持定义文件里的顺序，供调色板使用

	void _parse_block_file(const String &p_text);
	void _parse_op_file(const String &p_text);

protected:
	static void _bind_methods();

public:
	static BlockLibrary *get_singleton();
	/** 模块卸载时回收单例。 */
	static void destroy_singleton();

	/** 首次访问时自动加载内置定义（幂等）。 */
	void load_builtin();

	bool has_block(const String &p_id) const;
	Dictionary find_block(const String &p_id) const;
	bool has_op(const String &p_id) const;
	Dictionary find_op(const String &p_id) const;

	Array get_categories() const;
	Array get_extensions() const;
	PackedStringArray get_block_ids() const;
	PackedStringArray get_block_ids_in_category(const String &p_category) const;
	int get_block_count() const;
	int get_op_count() const;

	BlockLibrary();
	~BlockLibrary();
};
