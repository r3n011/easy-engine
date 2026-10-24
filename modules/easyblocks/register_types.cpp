/**************************************************************************/
/*  register_types.cpp                                                    */
/*  Easy Engine —— 模块注册                                                */
/**************************************************************************/

#include "register_types.h"

#include "block_library.h"
#include "block_program.h"
#include "block_runner.h"

#include "core/object/class_db.h"
#include "core/config/engine.h"

#ifdef TOOLS_ENABLED
#include "editor/easy_blocks_editor_plugin.h"
#include "editor/plugins/editor_plugin.h"
#endif

void initialize_easyblocks_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		GDREGISTER_CLASS(BlockLibrary);
		GDREGISTER_CLASS(BlockProgram);
		GDREGISTER_CLASS(BlockRunner);

		// 让积木定义在引擎里可全局访问（编辑器与运行时会话都用它）
		Engine::get_singleton()->add_singleton(
				Engine::Singleton("EasyBlocks", BlockLibrary::get_singleton(), "BlockLibrary"));
	}

#ifdef TOOLS_ENABLED
	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		// 把「积木」工作区装进 Godot 编辑器。
		// 这是String::utf8("改 Godot")而不是String::utf8("外挂")的关键：csg / multiplayer / navigation_2d
		// 也都是这么把界面加进编辑器的。
		EditorPlugins::add_by_type<EasyBlocksEditorPlugin>();
	}
#endif
}

void uninitialize_easyblocks_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->remove_singleton("EasyBlocks");
	BlockLibrary::destroy_singleton();
}
