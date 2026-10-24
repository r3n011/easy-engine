/**************************************************************************/
/*  easy_blocks_editor_plugin.cpp                                         */
/**************************************************************************/

#include "easy_blocks_editor_plugin.h"

#include "../block_library.h"

#include "core/string/ustring.h"
#include "scene/gui/label.h"
#include "scene/gui/margin_container.h"
#include "core/input/shortcut.h"
#include "core/os/os.h"
#include "scene/gui/box_container.h"

EasyBlocksEditorPlugin::EasyBlocksEditorPlugin() {
	MarginContainer *margin = memnew(MarginContainer);
	margin->set_name("EasyBlocksPanel");
	margin->add_theme_constant_override("margin_left", 8);
	margin->add_theme_constant_override("margin_top", 6);

	VBoxContainer *vb = memnew(VBoxContainer);
	margin->add_child(vb);

	Label *title = memnew(Label);
	title->set_text(String::utf8("Easy Engine · 积木"));
	vb->add_child(title);

	BlockLibrary *lib = BlockLibrary::get_singleton();
	lib->load_builtin();

	Label *info = memnew(Label);
	info->set_text(vformat(String::utf8("积木 %d 个 · op %d 个 · 分类 %d 个（B 阶段把工作区搬进来）"),
			lib->get_block_count(), lib->get_op_count(), lib->get_categories().size()));
	info->add_theme_color_override("font_color", Color(0.6, 0.68, 0.8));
	vb->add_child(info);

	panel = margin;
	add_control_to_bottom_panel(panel, String::utf8("积木"));

	// 演示/截图用：设了这个环境变量就直接把「积木」面板切到前台
	if (OS::get_singleton()->has_environment("EASYBLOCKS_SHOW_PANEL")) {
		// 构造时切太早，编辑器随后会重置底部面板，所以延后再切一次
		call_deferred(StringName("make_bottom_panel_item_visible"), panel);
	}
}

EasyBlocksEditorPlugin::~EasyBlocksEditorPlugin() {
	if (panel != nullptr) {
		remove_control_from_bottom_panel(panel);
		memdelete(panel);
		panel = nullptr;
	}
}
