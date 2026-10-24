/**************************************************************************/
/*  easy_blocks_editor_plugin.h                                           */
/*  Easy Engine —— 把「积木」装进 Godot 编辑器                              */
/**************************************************************************/

#pragma once

#include "editor/plugins/editor_plugin.h"

class Control;
class EasyBlocksWebView;
class BlockRunner;
class BlockProgram;

/**
 * 编辑器插件：在 Godot 编辑器里加一个「积木」底部面板。
 *
 * 面板里是一层 WebView2，网页用 Scratch 自己的积木渲染内核（scratch-blocks），
 * 所以积木的形状、拖拽手感、中文文案就是 Scratch 本身，用户不用重新学。
 *
 * 积木数据始终存在引擎这边（BlockProgram 资源，进 .tscn），网页只是编辑界面。
 */
class EasyBlocksEditorPlugin : public EditorPlugin {
	GDCLASS(EasyBlocksEditorPlugin, EditorPlugin);

	Control *panel = nullptr;
	EasyBlocksWebView *web_view = nullptr;

	// 当前选中的节点（积木就是"这个节点的脚本"）
	Node *current_node = nullptr;
	bool debug_bridge = false;

	void _on_selection_changed();
	void _on_page_message(const String &p_text);
	void _on_web_ready();
	void _push_program_to_page();
	void _apply_program(const Array &p_program, bool p_echo);

	Node *_active_node() const;
	BlockRunner *_find_runner(Node *p_node) const;
	BlockRunner *_ensure_runner(Node *p_node);

public:
	virtual String get_plugin_name() const override { return String::utf8("积木"); }
	virtual void edit(Object *p_object) override;
	virtual bool handles(Object *p_object) const override;

	EasyBlocksEditorPlugin();
	~EasyBlocksEditorPlugin();
};
