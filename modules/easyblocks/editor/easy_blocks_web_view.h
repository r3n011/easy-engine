/**************************************************************************/
/*  easy_blocks_web_view.h                                                */
/*  Easy Engine —— 内嵌 WebView2 的积木工作区控件                           */
/**************************************************************************/

#pragma once

#include "scene/gui/control.h"

/**
 * 一个把网页渲染进 Godot 编辑器面板的控件。
 *
 * 为什么是网页：积木编辑器直接用 Scratch 的渲染内核（scratch-blocks），
 * 形状、配色、拖拽手感、中文文案和 Scratch 一模一样 —— 用户不用重新学。
 *
 * 实现方式是 WebView2（Windows 自带 Edge 内核）。它不是"Godot 里画出来的"，
 * 而是叠在编辑器窗口上的原生子窗口，由本控件负责跟着面板的位置/大小/显隐同步。
 *
 * 平台：目前只有 Windows。其他平台这里是空实现（面板会提示）。
 */
class EasyBlocksWebView : public Control {
	GDCLASS(EasyBlocksWebView, Control);

	Callable bridge_callback;
	String web_root;
	int last_visibility = -1;

	void _sync_bounds();

#ifdef WINDOWS_ENABLED
	struct Impl;
	Impl *impl = nullptr;
#endif

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	/** 打开 web_root 目录下的 index.html。 */
	Error open(const String &p_web_root);
	void reload();
	/** 在页面里执行一段 JS。 */
	void eval(const String &p_js);
	/** 页面通过 window.chrome.webview.postMessage 发来的内容会交给它。 */
	void set_bridge_callback(const Callable &p_callback);
	bool is_ready() const;
	bool is_supported() const;

	/** WebView2 回调转发用（内部）。 */
	void _on_page_message(const String &p_text);
	void _on_ready();

	EasyBlocksWebView();
	~EasyBlocksWebView();
};
