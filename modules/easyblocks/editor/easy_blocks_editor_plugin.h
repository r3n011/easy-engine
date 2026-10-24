/**************************************************************************/
/*  easy_blocks_editor_plugin.h                                           */
/*  Easy Engine —— 把「积木」装进 Godot 编辑器                              */
/**************************************************************************/

#pragma once

#include "editor/plugins/editor_plugin.h"

class Control;

/**
 * 编辑器插件：在 Godot 编辑器里加一个「积木」底部面板。
 *
 * A 阶段只占位并显示积木库统计，用来验证String::utf8("界面确实长在 Godot 里")；
 * B 阶段把积木工作区（画布/调色板/拖拽吸附）搬进来。
 */
class EasyBlocksEditorPlugin : public EditorPlugin {
	GDCLASS(EasyBlocksEditorPlugin, EditorPlugin);

	Control *panel = nullptr;

public:
	virtual String get_plugin_name() const override { return String::utf8("积木"); }

	EasyBlocksEditorPlugin();
	~EasyBlocksEditorPlugin();
};
