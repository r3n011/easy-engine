/**************************************************************************/
/*  block_library.cpp                                                     */
/**************************************************************************/

#include "block_library.h"

#include "block_defs.gen.h"

#include "core/io/compression.h"
#include "core/io/json.h"
#include "core/object/class_db.h"
#include "core/object/object.h"


// 解压嵌入式定义（zlib）
static String _decompress(const unsigned char *p_src, int p_comp_size, int p_raw_size) {
	Vector<uint8_t> buf;
	buf.resize(p_raw_size + 1);
	const int64_t got = Compression::decompress(buf.ptrw(), p_raw_size, p_src, p_comp_size, Compression::MODE_DEFLATE);
	if (got < 0) {
		ERR_PRINT(String::utf8("EasyBlocks: 积木定义解压失败"));
		return String();
	}
	buf.write[p_raw_size] = 0;
	return String::utf8((const char *)buf.ptr(), p_raw_size);
}

BlockLibrary *BlockLibrary::singleton = nullptr;

BlockLibrary *BlockLibrary::get_singleton() {
	if (singleton == nullptr) {
		singleton = memnew(BlockLibrary);
	}
	return singleton;
}

void BlockLibrary::destroy_singleton() {
	if (singleton != nullptr) {
		memdelete(singleton);
		singleton = nullptr;
	}
}

void BlockLibrary::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load_builtin"), &BlockLibrary::load_builtin);
	ClassDB::bind_method(D_METHOD("has_block", "id"), &BlockLibrary::has_block);
	ClassDB::bind_method(D_METHOD("find_block", "id"), &BlockLibrary::find_block);
	ClassDB::bind_method(D_METHOD("has_op", "id"), &BlockLibrary::has_op);
	ClassDB::bind_method(D_METHOD("find_op", "id"), &BlockLibrary::find_op);
	ClassDB::bind_method(D_METHOD("get_categories"), &BlockLibrary::get_categories);
	ClassDB::bind_method(D_METHOD("get_extensions"), &BlockLibrary::get_extensions);
	ClassDB::bind_method(D_METHOD("get_block_ids"), &BlockLibrary::get_block_ids);
	ClassDB::bind_method(D_METHOD("get_block_ids_in_category", "category"), &BlockLibrary::get_block_ids_in_category);
	ClassDB::bind_method(D_METHOD("get_block_count"), &BlockLibrary::get_block_count);
	ClassDB::bind_method(D_METHOD("get_op_count"), &BlockLibrary::get_op_count);
}

void BlockLibrary::_parse_block_file(const String &p_text) {
	JSON json;
	if (json.parse(p_text) != OK) {
		ERR_PRINT(String::utf8("EasyBlocks: 积木定义 JSON 解析失败：") + json.get_error_message());
		return;
	}
	Dictionary root = json.get_data();
	if (root.is_empty()) {
		return;
	}

	const String ext = root.get("extension", String());
	Dictionary ext_info;
	ext_info["id"] = ext;
	ext_info["version"] = root.get("extensionVersion", 1);
	ext_info["description"] = root.get("description", String());
	if (!ext.is_empty()) {
		extensions.push_back(ext_info);
	}

	Array cats = root.get("categories", Array());
	for (int i = 0; i < cats.size(); i++) {
		Dictionary c = cats[i];
		if (c.is_empty()) {
			continue;
		}
		c["extension"] = ext;
		categories.push_back(c);
	}

	Array list = root.get("blocks", Array());
	for (int i = 0; i < list.size(); i++) {
		Dictionary b = list[i];
		String id = b.get("id", String());
		if (id.is_empty()) {
			continue;
		}
		b["extension"] = ext;
		if (!blocks.has(id)) {
			block_order.push_back(id);
		}
		blocks[id] = b;
	}
}

void BlockLibrary::_parse_op_file(const String &p_text) {
	JSON json;
	if (json.parse(p_text) != OK) {
		ERR_PRINT(String::utf8("EasyBlocks: op 定义 JSON 解析失败：") + json.get_error_message());
		return;
	}
	Dictionary root = json.get_data();
	if (root.is_empty()) {
		return;
	}
	const String ext = root.get("extension", String());
	Array list = root.get("ops", Array());
	for (int i = 0; i < list.size(); i++) {
		Dictionary o = list[i];
		String id = o.get("id", String());
		if (id.is_empty()) {
			continue;
		}
		o["extension"] = ext;
		ops[id] = o;
	}
}

void BlockLibrary::load_builtin() {
	if (loaded) {
		return;
	}
	loaded = true;

	// 定义是 zlib 压缩后嵌进二进制的（和引擎嵌翻译文件的做法一致）
	for (int i = 0; i < _eb_block_defs_count; i++) {
		_parse_block_file(_decompress(_eb_block_defs_data[i], _eb_block_defs_comp[i], _eb_block_defs_raw[i]));
	}
	for (int i = 0; i < _eb_op_defs_count; i++) {
		_parse_op_file(_decompress(_eb_op_defs_data[i], _eb_op_defs_comp[i], _eb_op_defs_raw[i]));
	}

	print_verbose(vformat(String::utf8("EasyBlocks: 已加载积木 %d 个、op %d 个、分类 %d 个"),
			blocks.size(), ops.size(), categories.size()));
}

bool BlockLibrary::has_block(const String &p_id) const {
	return blocks.has(p_id);
}

Dictionary BlockLibrary::find_block(const String &p_id) const {
	const Dictionary *d = blocks.getptr(p_id);
	return d ? *d : Dictionary();
}

bool BlockLibrary::has_op(const String &p_id) const {
	return ops.has(p_id);
}

Dictionary BlockLibrary::find_op(const String &p_id) const {
	const Dictionary *d = ops.getptr(p_id);
	return d ? *d : Dictionary();
}

Array BlockLibrary::get_categories() const {
	Array out;
	for (int i = 0; i < categories.size(); i++) {
		out.push_back(categories[i]);
	}
	return out;
}

Array BlockLibrary::get_extensions() const {
	Array out;
	for (int i = 0; i < extensions.size(); i++) {
		out.push_back(extensions[i]);
	}
	return out;
}

PackedStringArray BlockLibrary::get_block_ids() const {
	PackedStringArray out;
	for (int i = 0; i < block_order.size(); i++) {
		out.push_back(block_order[i]);
	}
	return out;
}

PackedStringArray BlockLibrary::get_block_ids_in_category(const String &p_category) const {
	PackedStringArray out;
	for (int i = 0; i < block_order.size(); i++) {
		const Dictionary *d = blocks.getptr(block_order[i]);
		if (d && String(d->get("category", String())) == p_category) {
			out.push_back(block_order[i]);
		}
	}
	return out;
}

int BlockLibrary::get_block_count() const {
	return blocks.size();
}

int BlockLibrary::get_op_count() const {
	return ops.size();
}

BlockLibrary::BlockLibrary() {
	load_builtin();
}

BlockLibrary::~BlockLibrary() {
	if (singleton == this) {
		singleton = nullptr;
	}
}
