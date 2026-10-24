/**************************************************************************/
/*  easy_blocks_editor_plugin.cpp                                         */
/**************************************************************************/

#include "easy_blocks_editor_plugin.h"

#include "../block_library.h"
#include "easy_blocks_web_view.h"

#include "core/input/shortcut.h"
#include "core/os/os.h"
#include "core/string/ustring.h"
#include "scene/gui/box_container.h"
#include "scene/gui/label.h"

EasyBlocksEditorPlugin::EasyBlocksEditorPlugin() {
	VBoxContainer *vb = memnew(VBoxContainer);
	vb->set_name("EasyBlocksPanel");

	// 积木工作区：内嵌 Scratch 的渲染内核。
	// 底部面板默认很矮，这里给个下限，让它一打开就像 Scratch 那样有一整块画布。
	web_view = memnew(EasyBlocksWebView);
	web_view->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	web_view->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	web_view->set_custom_minimum_size(Size2(0, 360));
	vb->add_child(web_view);

	// 网页资源随引擎放在可执行文件旁边（编译脚本会复制过去）
	const String web_root = OS::get_singleton()->get_executable_path().get_base_dir().path_join("easyblocks_web");
	const Error err = web_view->open(web_root);

	if (err != OK) {
		Label *fail = memnew(Label);
		if (!web_view->is_supported()) {
			fail->set_text(String::utf8("积木工作区目前只支持 Windows（用系统自带的 Edge 内核渲染）。"));
		} else {
			fail->set_text(String::utf8("没能打开积木工作区网页：") + web_root +
					String::utf8("\n如果本机缺少 Edge WebView2 运行时，装好再试。"));
		}
		vb->add_child(fail);
	}

	BlockLibrary *lib = BlockLibrary::get_singleton();
	lib->load_builtin();

	panel = vb;
	add_control_to_bottom_panel(panel, String::utf8("积木"));

	// 演示/截图用：设了这个环境变量就把「积木」面板直接切到前台
	if (OS::get_singleton()->has_environment("EASYBLOCKS_SHOW_PANEL")) {
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
