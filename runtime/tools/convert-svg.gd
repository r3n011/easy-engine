# 用 Godot 内置的 SVG 渲染把 .svg 转成 .png，便于查看与切分。
#
# 用法:
#   godot --headless --path runtime --script tools/convert-svg.gd -- <in.svg> <out.png> [scale]

extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("用法: -- <in.svg> <out.png> [scale]")
		quit(1)
		return
	var src := args[0]
	var dst := args[1]
	var scale := float(args[2]) if args.size() > 2 else 1.0

	var fa := FileAccess.open(src, FileAccess.READ)
	if fa == null:
		print("打不开: " + src)
		quit(1)
		return
	var text := fa.get_as_text()
	fa.close()

	var img := Image.new()
	var err := img.load_svg_from_string(text, scale)
	if err != OK:
		print("SVG 解析失败，错误码 %d" % err)
		quit(1)
		return

	err = img.save_png(dst)
	if err != OK:
		print("写 PNG 失败，错误码 %d" % err)
		quit(1)
		return
	print("已转换: %s -> %s  (%d x %d)" % [src, dst, img.get_width(), img.get_height()])
	quit(0)
