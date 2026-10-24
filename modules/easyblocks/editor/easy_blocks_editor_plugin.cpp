/**************************************************************************/
/*  easy_blocks_editor_plugin.cpp                                         */
/**************************************************************************/

#include "easy_blocks_editor_plugin.h"

#include "../block_program.h"
#include "../block_runner.h"
#include "easy_blocks_web_view.h"

#include "core/input/shortcut.h"
#include "core/object/callable_mp.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/os/os.h"
#include "core/string/ustring.h"
#include "editor/editor_interface.h"
#include "editor/editor_data.h"
#include "scene/gui/box_container.h"
#include "scene/gui/label.h"

EasyBlocksEditorPlugin::EasyBlocksEditorPlugin() {
	debug_bridge = OS::get_singleton()->has_environment("EASYBLOCKS_DEBUG");
	VBoxContainer *vb = memnew(VBoxContainer);
	vb->set_name("EasyBlocksPanel");

	// 底部面板默认很矮，给个下限，让它一打开就像 Scratch 那样有一整块画布
	web_view = memnew(EasyBlocksWebView);
	web_view->set_v_size_flags(Control::SIZE_EXPAND_FILL);
	web_view->set_h_size_flags(Control::SIZE_EXPAND_FILL);
	web_view->set_custom_minimum_size(Size2(0, 360));
	vb->add_child(web_view);

	web_view->set_bridge_callback(callable_mp(this, &EasyBlocksEditorPlugin::_on_page_message));
	web_view->connect("web_ready", callable_mp(this, &EasyBlocksEditorPlugin::_on_web_ready));

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

	panel = vb;
	add_control_to_bottom_panel(panel, String::utf8("积木"));

	// 选中节点 → 显示它挂的积木
	EditorSelection *sel = EditorInterface::get_singleton()->get_selection();
	if (sel != nullptr) {
		sel->connect("selection_changed", callable_mp(this, &EasyBlocksEditorPlugin::_on_selection_changed));
	}

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

// ============================================================ 选中联动

void EasyBlocksEditorPlugin::edit(Object *p_object) {
	current_node = Object::cast_to<Node>(p_object);
	_push_program_to_page();
}

bool EasyBlocksEditorPlugin::handles(Object *p_object) const {
	return Object::cast_to<Node>(p_object) != nullptr;
}

void EasyBlocksEditorPlugin::_on_selection_changed() {
	EditorSelection *sel = EditorInterface::get_singleton()->get_selection();
	if (sel == nullptr) {
		return;
	}
	const TypedArray<Node> nodes = sel->get_selected_nodes();
	current_node = (nodes.size() == 1) ? Object::cast_to<Node>(nodes[0]) : nullptr;
	_push_program_to_page();
}

Node *EasyBlocksEditorPlugin::_active_node() const {
	if (current_node != nullptr) {
		return current_node;
	}
	return EditorInterface::get_singleton()->get_edited_scene_root();
}

BlockRunner *EasyBlocksEditorPlugin::_find_runner(Node *p_node) const {
	if (p_node == nullptr) {
		return nullptr;
	}
	BlockRunner *self_runner = Object::cast_to<BlockRunner>(p_node);
	if (self_runner != nullptr) {
		return self_runner;
	}
	for (int i = 0; i < p_node->get_child_count(); i++) {
		BlockRunner *child = Object::cast_to<BlockRunner>(p_node->get_child(i));
		if (child != nullptr) {
			return child;
		}
	}
	return nullptr;
}

BlockRunner *EasyBlocksEditorPlugin::_ensure_runner(Node *p_node) {
	BlockRunner *runner = _find_runner(p_node);
	if (runner != nullptr) {
		if (runner->get_program().is_null()) {
			Ref<BlockProgram> program;
			program.instantiate();
			runner->set_program(program);
		}
		return runner;
	}

	// 这个节点还没有积木：第一次写积木时自动挂一个运行器。
	// 用 lazy 的方式（等真有积木才建），避免"点一下节点就多一个子节点"。
	runner = memnew(BlockRunner);
	runner->set_name("BlockRunner");
	p_node->add_child(runner);

	Node *root = EditorInterface::get_singleton()->get_edited_scene_root();
	if (root != nullptr && root != p_node) {
		runner->set_owner(root);
	}

	Ref<BlockProgram> program;
	program.instantiate();
	runner->set_program(program);
	return runner;
}

// ============================================================ 引擎 <-> 网页

void EasyBlocksEditorPlugin::_push_program_to_page() {
	if (web_view == nullptr || !web_view->is_ready()) {
		return;
	}

	Array scripts;
	Node *target = _active_node();
	BlockRunner *runner = _find_runner(target);
	if (runner != nullptr) {
		Ref<BlockProgram> program = runner->get_program();
		// 没挂资源但给了 JSON 文件的（A 阶段的测试工程、手写的积木）也认
		if (program.is_null() && !runner->get_program_json_path().is_empty()) {
			Ref<FileAccess> f = FileAccess::open(runner->get_program_json_path(), FileAccess::READ);
			if (f.is_valid()) {
				Ref<BlockProgram> loaded;
				loaded.instantiate();
				if (loaded->set_scripts_json(f->get_as_text()) == OK) {
					runner->set_program(loaded);
					program = loaded;
				}
			}
		}
		if (program.is_valid()) {
			scripts = program->get_scripts();
		}
	}

	// 直接拼成 JS 数组字面量喂进去（JSON 就是合法的 JS 字面量）
	if (debug_bridge) {
		print_line(vformat(String::utf8("积木桥：节点=%s 脚本=%d 段"),
				target ? String(target->get_name()) : String("<null>"), scripts.size()));
	}
	web_view->eval("window.eeLoadProgram(" + JSON::stringify(scripts, "", false, true) + ")");

	if (current_node == nullptr) {
		web_view->eval("window.eeToast && window.eeToast('先在场景里选中一个节点，积木会存到它身上')");
	}
}

void EasyBlocksEditorPlugin::_on_web_ready() {
	_push_program_to_page();
}

void EasyBlocksEditorPlugin::_apply_program(const Array &p_program, bool p_echo) {
	Node *target = _active_node();
	if (target == nullptr) {
		return;
	}

	BlockRunner *runner = _ensure_runner(target);
	if (runner == nullptr) {
		return;
	}

	Ref<BlockProgram> program = runner->get_program();
	if (program.is_null()) {
		program.instantiate();
		runner->set_program(program);
	}

	program->set_scripts(p_program);
	const Error err = program->compile();
	if (err != OK) {
		const Array errors = program->get_errors();
		for (int i = 0; i < errors.size(); i++) {
			Dictionary e = errors[i];
			ERR_PRINT(String::utf8("积木编译失败：") + String(e.get("message", String())));
		}
	} else {
		if (debug_bridge) {
			print_line(vformat(String::utf8("积木桥：已保存到 %s，%d 段脚本，IR %d 条"),
					target->get_name(), p_program.size(), program->get_ir().size()));
			print_line("积木桥：IR = " + JSON::stringify(program->get_ir(), "", false, true));
		}
	}

	if (!p_echo) {
		EditorInterface::get_singleton()->mark_scene_as_unsaved();
	} else {
		if (debug_bridge) {
			print_line(vformat(String::utf8("积木往返校验：网页回显 %d 段，编译 %s"),
					p_program.size(), err == OK ? String::utf8("通过") : String::utf8("有错")));
		}
	}
}

void EasyBlocksEditorPlugin::_on_page_message(const String &p_text) {
	JSON json;
	if (json.parse(p_text) != OK) {
		return;
	}
	Dictionary msg = json.get_data();
	const String type = msg.get("type", String());

	if (type == "js_error") {
		ERR_PRINT(String::utf8("积木工作区脚本报错：") + String(msg.get("message", String())));
		return;
	}

	if (type == "ready" || type == "bridge_ready") {
		_push_program_to_page();
		return;
	}

	if (type == "program") {
		Array program = msg.get("program", Array());
		Array unsupported = msg.get("unsupported", Array());
		if (!unsupported.is_empty()) {
			// 有积木还没接进引擎：这类积木在保存时被跳过，必须说清楚，不能静默丢
			String names;
			for (int i = 0; i < unsupported.size(); i++) {
				if (i > 0) {
					names += String::utf8("、");
				}
				names += String(unsupported[i]);
			}
			WARN_PRINT(String::utf8("这些积木暂时还不支持，已跳过：") + names);
		}
		if (msg.get("echo", false)) {
			Array tops = msg.get("tops", Array());
			String dbg;
			for (int i = 0; i < tops.size(); i++) {
				if (i > 0) dbg += ", ";
				dbg += String(tops[i]);
			}
			if (debug_bridge) {
				print_line(String::utf8("积木桥诊断：顶层积木 = ") + dbg);
			}
		}
		const bool echo = msg.get("echo", false);
		_apply_program(program, echo);
	}
}
