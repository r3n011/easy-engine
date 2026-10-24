/**************************************************************************/
/*  easy_blocks_web_view.cpp                                              */
/**************************************************************************/

#include "easy_blocks_web_view.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "servers/display/display_server.h"

#ifdef WINDOWS_ENABLED
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include <functional>

#include <wrl/client.h>

#include "WebView2.h"
#endif

void EasyBlocksWebView::_bind_methods() {
	ClassDB::bind_method(D_METHOD("open", "web_root"), &EasyBlocksWebView::open);
	ClassDB::bind_method(D_METHOD("reload"), &EasyBlocksWebView::reload);
	ClassDB::bind_method(D_METHOD("eval", "js"), &EasyBlocksWebView::eval);
	ClassDB::bind_method(D_METHOD("set_bridge_callback", "callback"), &EasyBlocksWebView::set_bridge_callback);
	ClassDB::bind_method(D_METHOD("is_ready"), &EasyBlocksWebView::is_ready);
	ClassDB::bind_method(D_METHOD("is_supported"), &EasyBlocksWebView::is_supported);
	ClassDB::bind_method(D_METHOD("_on_page_message", "text"), &EasyBlocksWebView::_on_page_message);
	ClassDB::bind_method(D_METHOD("_on_ready"), &EasyBlocksWebView::_on_ready);

	ADD_SIGNAL(MethodInfo("web_ready"));
}

// ============================================================ Windows 实现

#ifdef WINDOWS_ENABLED

using Microsoft::WRL::ComPtr;

static const wchar_t *EE_HOST_CLASS = L"EasyBlocksWebViewHost";
static const wchar_t *EE_VIRTUAL_HOST = L"easyblocks.local";
static bool ee_host_class_registered = false;

// --- 最小可用的 COM 回调实现 ---
// 没用 Microsoft::WRL::Callback：这个 Windows SDK 的 wrl 里没有它。
// 自己写反而更可控，也少一个依赖。

template <typename TInterface>
class EERefCounted : public TInterface {
	volatile LONG ref_count = 1;

public:
	STDMETHODIMP QueryInterface(REFIID riid, void **ppv) override {
		if (ppv == nullptr) {
			return E_POINTER;
		}
		if (riid == __uuidof(TInterface) || riid == IID_IUnknown) {
			*ppv = static_cast<TInterface *>(this);
			AddRef();
			return S_OK;
		}
		*ppv = nullptr;
		return E_NOINTERFACE;
	}
	STDMETHODIMP_(ULONG) AddRef() override {
		return (ULONG)InterlockedIncrement(&ref_count);
	}
	STDMETHODIMP_(ULONG) Release() override {
		const ULONG left = (ULONG)InterlockedDecrement(&ref_count);
		if (left == 0) {
			delete this;
		}
		return left;
	}
};

class EECreateEnvHandler : public EERefCounted<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler> {
public:
	std::function<HRESULT(HRESULT, ICoreWebView2Environment *)> callback;
	HRESULT STDMETHODCALLTYPE Invoke(HRESULT p_result, ICoreWebView2Environment *p_env) override {
		return callback ? callback(p_result, p_env) : S_OK;
	}
};

class EECreateControllerHandler : public EERefCounted<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler> {
public:
	std::function<HRESULT(HRESULT, ICoreWebView2Controller *)> callback;
	HRESULT STDMETHODCALLTYPE Invoke(HRESULT p_result, ICoreWebView2Controller *p_ctrl) override {
		return callback ? callback(p_result, p_ctrl) : S_OK;
	}
};

class EEMessageHandler : public EERefCounted<ICoreWebView2WebMessageReceivedEventHandler> {
public:
	std::function<HRESULT(ICoreWebView2WebMessageReceivedEventArgs *)> callback;
	HRESULT STDMETHODCALLTYPE Invoke(ICoreWebView2 *, ICoreWebView2WebMessageReceivedEventArgs *p_args) override {
		return callback ? callback(p_args) : S_OK;
	}
};

class EENavigationHandler : public EERefCounted<ICoreWebView2NavigationCompletedEventHandler> {
public:
	std::function<HRESULT(ICoreWebView2NavigationCompletedEventArgs *)> callback;
	HRESULT STDMETHODCALLTYPE Invoke(ICoreWebView2 *, ICoreWebView2NavigationCompletedEventArgs *p_args) override {
		return callback ? callback(p_args) : S_OK;
	}
};

struct EasyBlocksWebView::Impl {
	HWND parent_hwnd = nullptr;
	HWND host_hwnd = nullptr;

	ComPtr<ICoreWebView2Environment> env;
	ComPtr<ICoreWebView2Controller> controller;
	ComPtr<ICoreWebView2> webview;

	// 上次同步过的矩形（父窗口客户区坐标 + 尺寸），避免每帧 SetWindowPos 造成闪烁
	Rect2i rect = Rect2i(0, 0, -1, -1);
	bool controller_ready = false;
	bool com_inited = false;
	String pending_js;
};

static LRESULT CALLBACK _ee_host_wndproc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
	switch (msg) {
		case WM_SETFOCUS: {
			// 焦点交给 WebView2 内部窗口，键盘与输入法直接进网页
			HWND child = GetWindow(hwnd, GW_CHILD);
			if (child != nullptr) {
				SetFocus(child);
			}
			return 0;
		}
		case WM_ERASEBKGND:
			return 1; // 网页会自己铺满，别擦背景免得闪
		default:
			return DefWindowProcW(hwnd, msg, wparam, lparam);
	}
}

// WebView2Loader.dll 动态加载。
// 不直接链 WebView2LoaderStatic.lib：Godot 的 SCons 会给 LIBS 里的名字加平台后缀，
// .lib 路径塞进 LINKFLAGS 又容易被改写。动态加载最稳，也方便报"缺运行时"的错。
typedef HRESULT(STDAPICALLTYPE *EE_PFN_CreateEnvironment)(PCWSTR, PCWSTR,
		ICoreWebView2EnvironmentOptions *, ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *);

static HMODULE ee_loader_module = nullptr;
static EE_PFN_CreateEnvironment ee_create_environment = nullptr;

static bool _ee_load_loader_dll() {
	if (ee_create_environment != nullptr) {
		return true;
	}
	const String exe_dir = OS::get_singleton()->get_executable_path().get_base_dir();
	const Char16String dll_path = exe_dir.path_join("WebView2Loader.dll").utf16();
	ee_loader_module = LoadLibraryW((LPCWSTR)dll_path.get_data());
	if (ee_loader_module == nullptr) {
		ee_loader_module = LoadLibraryW(L"WebView2Loader.dll");
	}
	if (ee_loader_module == nullptr) {
		ERR_PRINT(String::utf8("EasyBlocks: 找不到 WebView2Loader.dll（应该和 godot.exe 放在一起）"));
		return false;
	}
	ee_create_environment = (EE_PFN_CreateEnvironment)GetProcAddress(ee_loader_module,
			"CreateCoreWebView2EnvironmentWithOptions");
	if (ee_create_environment == nullptr) {
		ERR_PRINT(String::utf8("EasyBlocks: WebView2Loader.dll 里没有 CreateCoreWebView2EnvironmentWithOptions"));
		return false;
	}
	return true;
}
static bool _ee_register_host_class() {
	if (ee_host_class_registered) {
		return true;
	}
	WNDCLASSEXW wc = {};
	wc.cbSize = sizeof(WNDCLASSEXW);
	wc.lpfnWndProc = _ee_host_wndproc;
	wc.hInstance = GetModuleHandleW(nullptr);
	wc.hCursor = LoadCursorW(nullptr, (LPCWSTR)IDC_ARROW);
	wc.lpszClassName = EE_HOST_CLASS;
	if (RegisterClassExW(&wc) == 0) {
		return false;
	}
	ee_host_class_registered = true;
	return true;
}

Error EasyBlocksWebView::open(const String &p_web_root) {
	web_root = p_web_root;

	const String index_path = p_web_root.path_join("index.html");
	if (!FileAccess::exists(index_path)) {
		ERR_PRINT(vformat(String::utf8("EasyBlocks: 找不到积木工作区网页：%s"), index_path));
		return ERR_FILE_NOT_FOUND;
	}

	if (!_ee_register_host_class()) {
		ERR_PRINT(String::utf8("EasyBlocks: 注册 WebView2 宿主窗口类失败"));
		return FAILED;
	}

	// 编辑器主窗口：WebView2 的宿主窗口挂成它的子窗口
	DisplayServer *ds = DisplayServer::get_singleton();
	const HWND parent = (HWND)(uintptr_t)ds->window_get_native_handle(
			DisplayServerEnums::WINDOW_HANDLE, DisplayServerEnums::MAIN_WINDOW_ID);
	if (parent == nullptr) {
		ERR_PRINT(String::utf8("EasyBlocks: 拿不到编辑器窗口句柄"));
		return FAILED;
	}

	if (impl == nullptr) {
		impl = memnew(Impl);
	}
	impl->parent_hwnd = parent;

	if (impl->host_hwnd == nullptr) {
		impl->host_hwnd = CreateWindowExW(0, EE_HOST_CLASS, L"",
				WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS,
				0, 0, 1, 1, parent, nullptr, GetModuleHandleW(nullptr), nullptr);
		if (impl->host_hwnd == nullptr) {
			ERR_PRINT(String::utf8("EasyBlocks: 创建 WebView2 宿主窗口失败"));
			return FAILED;
		}
		ShowWindow(impl->host_hwnd, SW_SHOWNA);
	}

	// WebView2 要求调用线程初始化过 COM，并且有消息循环（Godot 主线程两者都满足）
	const HRESULT hr_com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
	if (hr_com == S_OK || hr_com == S_FALSE) {
		impl->com_inited = true;
	}

	// WebView2 需要可写的数据目录放缓存
	const String data_dir = OS::get_singleton()->get_data_path().path_join("easyblocks_webview");
	DirAccess::make_dir_recursive_absolute(data_dir);

	const Char16String data_dir_utf16 = data_dir.utf16();
	const Char16String root_utf16 = p_web_root.simplify_path().utf16();

	EECreateEnvHandler *env_handler = new EECreateEnvHandler();
	env_handler->callback = [this, root_utf16](HRESULT p_result, ICoreWebView2Environment *p_env) -> HRESULT {
		if (FAILED(p_result) || p_env == nullptr) {
			ERR_PRINT(String::utf8("EasyBlocks: WebView2 环境创建失败（本机可能没装 Edge WebView2 运行时）"));
			return S_OK;
		}
		impl->env = p_env;

		EECreateControllerHandler *ctrl_handler = new EECreateControllerHandler();
		ctrl_handler->callback = [this, root_utf16](HRESULT p_r2, ICoreWebView2Controller *p_ctrl) -> HRESULT {
			if (FAILED(p_r2) || p_ctrl == nullptr) {
				ERR_PRINT(String::utf8("EasyBlocks: WebView2 控制器创建失败"));
				return S_OK;
			}
			impl->controller = p_ctrl;
			impl->controller->get_CoreWebView2(&impl->webview);
			if (impl->webview == nullptr) {
				return S_OK;
			}

			// 去掉浏览器味：右键菜单、状态栏、缩放、开发者工具、错误页全都关掉
			ComPtr<ICoreWebView2Settings> settings;
			if (SUCCEEDED(impl->webview->get_Settings(&settings)) && settings != nullptr) {
				settings->put_AreDefaultContextMenusEnabled(FALSE);
				settings->put_AreDevToolsEnabled(FALSE);
				settings->put_IsStatusBarEnabled(FALSE);
				settings->put_IsZoomControlEnabled(FALSE);
				settings->put_IsBuiltInErrorPageEnabled(FALSE);
			}

			// 把本地目录映射成一个"网站"：index.html 里的相对路径、模块加载都能正常工作。
			// 这个接口在 ICoreWebView2_3 上，得先 QI。
			ComPtr<ICoreWebView2_3> webview3;
			if (SUCCEEDED(impl->webview.As(&webview3)) && webview3 != nullptr) {
				webview3->SetVirtualHostNameToFolderMapping(
						EE_VIRTUAL_HOST, (LPCWSTR)root_utf16.get_data(),
						COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
			} else {
				ERR_PRINT(String::utf8("EasyBlocks: 当前 WebView2 版本太旧，缺少虚拟主机映射接口"));
			}

			// 页面 → 引擎
			EEMessageHandler *msg_handler = new EEMessageHandler();
			msg_handler->callback = [this](ICoreWebView2WebMessageReceivedEventArgs *p_args) -> HRESULT {
				LPWSTR raw = nullptr;
				if (FAILED(p_args->get_WebMessageAsJson(&raw)) || raw == nullptr) {
					return S_OK;
				}
				const String text = String::utf16((const char16_t *)raw);
				CoTaskMemFree(raw);
				// 这个回调不在引擎的帧节奏里，交给下一帧处理
				call_deferred(StringName("_on_page_message"), text);
				return S_OK;
			};
			EventRegistrationToken msg_token = {};
			impl->webview->add_WebMessageReceived(msg_handler, &msg_token);
			msg_handler->Release();

			// 页面加载完 → 通知上层
			EENavigationHandler *nav_handler = new EENavigationHandler();
			nav_handler->callback = [this](ICoreWebView2NavigationCompletedEventArgs *p_e) -> HRESULT {
				BOOL ok = FALSE;
				p_e->get_IsSuccess(&ok);
				if (!ok) {
					ERR_PRINT(String::utf8("EasyBlocks: 积木工作区网页加载失败"));
					return S_OK;
				}
				impl->controller_ready = true;
				call_deferred(StringName("_on_ready"));
				if (!impl->pending_js.is_empty()) {
					const String js = impl->pending_js;
					impl->pending_js = String();
					eval(js);
				}
				return S_OK;
			};
			EventRegistrationToken nav_token = {};
			impl->webview->add_NavigationCompleted(nav_handler, &nav_token);
			nav_handler->Release();

			impl->webview->Navigate(L"https://easyblocks.local/index.html");
			return S_OK;
		};
		impl->env->CreateCoreWebView2Controller(impl->host_hwnd, ctrl_handler);
		ctrl_handler->Release();
		return S_OK;
	};

	if (!_ee_load_loader_dll()) {
		env_handler->Release();
		return FAILED;
	}
	ee_create_environment(
			nullptr, (LPCWSTR)data_dir_utf16.get_data(), nullptr, env_handler);
	env_handler->Release();

	return OK;
}

void EasyBlocksWebView::reload() {
	if (impl != nullptr && impl->webview != nullptr) {
		impl->webview->Reload();
	}
}

void EasyBlocksWebView::eval(const String &p_js) {
	if (impl == nullptr) {
		return;
	}
	if (impl->webview == nullptr || !impl->controller_ready) {
		impl->pending_js = p_js;
		return;
	}
	const Char16String js = p_js.utf16();
	impl->webview->ExecuteScript((LPCWSTR)js.get_data(), nullptr);
}

bool EasyBlocksWebView::is_ready() const {
	return impl != nullptr && impl->controller_ready;
}

bool EasyBlocksWebView::is_supported() const {
	return true;
}

void EasyBlocksWebView::_sync_bounds() {
	if (impl == nullptr || impl->host_hwnd == nullptr) {
		return;
	}

	const bool visible = is_visible_in_tree() && is_visible();
	if (!visible) {
		if (impl->rect.size.width != -1) {
			impl->rect = Rect2i(0, 0, -1, -1);
			if (impl->controller != nullptr) {
				impl->controller->put_IsVisible(FALSE);
			}
			ShowWindow(impl->host_hwnd, SW_HIDE);
		}
		return;
	}

	const Point2i screen_pos = get_screen_position();
	const Size2i size = get_size();

	POINT pt = { (LONG)screen_pos.x, (LONG)screen_pos.y };
	ScreenToClient(impl->parent_hwnd, &pt);

	const Rect2i target(pt.x, pt.y, MAX(1, size.width), MAX(1, size.height));
	// 每帧都动窗口会闪，只在真的变了才动
	if (target == impl->rect) {
		return;
	}
	impl->rect = target;

	ShowWindow(impl->host_hwnd, SW_SHOWNA);
	if (impl->controller != nullptr) {
		impl->controller->put_IsVisible(TRUE);
	}

	SetWindowPos(impl->host_hwnd, nullptr, pt.x, pt.y, target.size.width, target.size.height,
			SWP_NOZORDER | SWP_NOACTIVATE);

	if (impl->controller != nullptr) {
		RECT rc = { 0, 0, (LONG)target.size.width, (LONG)target.size.height };
		impl->controller->put_Bounds(rc);
	}
}

#else // 非 Windows

Error EasyBlocksWebView::open(const String &p_web_root) {
	web_root = p_web_root;
	return ERR_UNAVAILABLE;
}
void EasyBlocksWebView::reload() {}
void EasyBlocksWebView::eval(const String &p_js) { (void)p_js; }
bool EasyBlocksWebView::is_ready() const { return false; }
bool EasyBlocksWebView::is_supported() const { return false; }
void EasyBlocksWebView::_sync_bounds() {}

#endif // WINDOWS_ENABLED

// ============================================================ 通用

void EasyBlocksWebView::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			connect("item_rect_changed", callable_mp(this, &EasyBlocksWebView::_sync_bounds));
			connect("visibility_changed", callable_mp(this, &EasyBlocksWebView::_sync_bounds));
			_sync_bounds();
		} break;
		case NOTIFICATION_PROCESS: {
			// 底部面板折叠、编辑器窗口移动这类变化不一定有信号，兜一层轻量同步
			_sync_bounds();
		} break;
		case NOTIFICATION_VISIBILITY_CHANGED: {
			_sync_bounds();
		} break;
		default:
			break;
	}
}

void EasyBlocksWebView::set_bridge_callback(const Callable &p_callback) {
	bridge_callback = p_callback;
}

void EasyBlocksWebView::_on_page_message(const String &p_text) {
	if (bridge_callback.is_valid()) {
		bridge_callback.call(p_text);
	}
}

void EasyBlocksWebView::_on_ready() {
	// 握手：告诉页面引擎这边准备好了
	eval("window.eeBridge && window.eeBridge.engineReady && window.eeBridge.engineReady()");
	emit_signal(SNAME("web_ready"));
}

EasyBlocksWebView::EasyBlocksWebView() {
	set_process(true);
	set_clip_contents(true);
	set_focus_mode(FOCUS_ALL);
}

EasyBlocksWebView::~EasyBlocksWebView() {
#ifdef WINDOWS_ENABLED
	if (impl != nullptr) {
		if (impl->controller != nullptr) {
			impl->controller->Close();
		}
		impl->webview.Reset();
		impl->controller.Reset();
		impl->env.Reset();
		if (impl->host_hwnd != nullptr) {
			DestroyWindow(impl->host_hwnd);
		}
		if (impl->com_inited) {
			CoUninitialize();
		}
		memdelete(impl);
		impl = nullptr;
	}
#endif
}
