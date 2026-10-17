# 离屏验证 Godot 翻译：直接按 (上下文, 原文) 查询，确认返回中文。
#
# 运行:
#   godot.windows.editor.x86_64.exe --headless --path tools/verify-translation --script verify.gd
#
# 原理：运行时查找是 Translation::get_message(msgid, context)，键为
# {msgctxt, msgid} 精确匹配、无回退（见 core/string/translation.cpp）。
# 因此只要这里查得到中文，界面上就一定是中文。

extends SceneTree

const CASES := [
	# [po 文件, 上下文, 原文, 期望译文]
	["res://zh_Hans.editor.po", "Editor Theme Style", "Modern", "现代"],
	["res://zh_Hans.editor.po", "Editor Theme Style", "Classic", "经典"],
	["res://zh_Hans.editor.po", "Editor Color Preset", "Default", "默认"],
	["res://zh_Hans.editor.po", "Editor Color Preset", "Black (OLED)", "黑色（OLED）"],
	["res://zh_Hans.editor.po", "", "Auto (%s)", "自动（%s）"],
	["res://zh_Hans.editor.po", "Display Scale", "Custom", "自定义"],
	["res://zh_Hans.editor.po", "Network Mode", "Offline", "离线"],
	["res://zh_Hans.editor.po", "Network Mode", "Online", "在线"],
	["res://zh_Hans.editor.po", "Check for Updates", "Auto (Stable)", "自动（稳定版）"],
	["res://zh_Hans.editor.po", "Check for Updates", "Check Newest Patch", "检查最新补丁"],
	["res://zh_Hans.editor.po", "Directory Naming Convention", "No Convention", "无规范"],
	["res://zh_Hans.editor.po", "Directory Naming Convention", "Title Case", "标题式"],
	# 上下文不一致时必须查不到（验证"精确匹配、无回退"）
	["res://zh_Hans.editor.po", "编辑器主题样式", "Modern", ""],
	# 上游原有译文仍然有效
	["res://zh_Hans.editor.po", "Transition Type", "Spring", "弹簧"],
	["res://zh_Hans.editor.po", "Bezier Handle Mode", "Mirrored", "镜像"],
	# 补翻的 extractable 条目
	["res://zh_Hans.extractable.po", "", "Hex", "十六进制"],
	["res://zh_Hans.extractable.po", "", "Swatches", "色板"],
	["res://zh_Hans.extractable.po", "", "Recent:", "最近使用："],
	["res://zh_Hans.extractable.po", "", "Sort by Name (Ascending)", "按名称排序（升序）"],
]


func _init() -> void:
	var cache := {}
	var passed := 0
	var failed := 0

	for c in CASES:
		var path: String = c[0]
		if not cache.has(path):
			var res: Translation = ResourceLoader.load(path)
			if res == null:
				print("!! 无法加载 %s" % path)
				failed += 1
				cache[path] = null
				continue
			cache[path] = res

		var tr: Translation = cache[path]
		if tr == null:
			continue

		var got: String = String(tr.get_message(StringName(c[2]), StringName(c[1])))
		var want: String = c[3]
		var label := "[" + String(c[1]) + "] " + String(c[2])
		if got == want:
			passed += 1
			print("  OK   " + label + "  ->  " + got)
		else:
			failed += 1
			print("  FAIL " + label + "  期望=" + want + "  实际=" + got)

	print("")
	print("通过 " + str(passed) + "，失败 " + str(failed))
	quit(0 if failed == 0 else 1)
