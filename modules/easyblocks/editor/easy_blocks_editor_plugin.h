/**************************************************************************/
/*  easy_blocks_editor_plugin.h                                           */
/*  Easy Engine —— 把「积木」装进 Godot 编辑器                              */
/**************************************************************************/

#pragma once

#include "editor/plugins/editor_plugin.h"

class Control;
class EasyBlocksWebView;

/**
 * 编辑器插件：在 Godot 编辑器里加一个「积木」底部面板。
 *
 * 面板里是一层 WebView2，网页用 Scratch 自己的积木渲染内核（scratch-blocks），
 * 所以积木的形状、拖拽手感、中文文案就是 Scratch 本身，用户不用重新学。
 */
class EasyBlocksEditorPlugin : public EditorPlugin {
	GDCLASS(EasyBlocksEditorPlugin, EditorPlugin);

	Control *panel = nullptr;
	EasyBlocksWebView *web_view = nullptr;

public:
	virtual String get_plugin_name() const override { return String::utf8("积木"); }

	EasyBlocksEditorPlugin();
	~EasyBlocksEditorPlugin();
};
