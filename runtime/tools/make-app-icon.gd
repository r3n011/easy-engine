# 由 logo 图标合成方形应用图标（启动画面 / exe 图标用）。
#
# 用法:
#   godot --headless --path runtime --script tools/make-app-icon.gd -- <icon.png> <out.png> <边长> [底色hex]

extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		print("用法: -- <icon.png> <out.png> <size> [bg_hex]")
		quit(1)
		return
	var src := args[0]
	var dst := args[1]
	var size := int(args[2])
	var bg_hex := args[3] if args.size() > 3 else ""

	var icon := Image.load_from_file(src)
	if icon == null:
		print("读不到图标: " + src)
		quit(1)
		return

	var canvas := Image.create(size, size, false, Image.FORMAT_RGBA8)
	if bg_hex.is_empty():
		canvas.fill(Color(0, 0, 0, 0))
	else:
		canvas.fill(Color.html(bg_hex))

	# 图标缩放到画布的 76%，居中
	var target := int(size * 0.76)
	var scale := float(target) / float(maxi(icon.get_width(), icon.get_height()))
	var w := int(icon.get_width() * scale)
	var h := int(icon.get_height() * scale)
	icon.resize(w, h, Image.INTERPOLATE_LANCZOS)
	canvas.blend_rect(icon, Rect2i(0, 0, w, h), Vector2i((size - w) / 2, (size - h) / 2))

	var err := canvas.save_png(dst)
	if err != OK:
		print("写 PNG 失败，错误码 %d" % err)
		quit(1)
		return
	print("已生成: %s  (%d x %d，底色 %s)" % [dst, size, size, bg_hex if not bg_hex.is_empty() else "透明"])
	quit(0)
