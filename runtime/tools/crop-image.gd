# 裁剪并放大图片的指定区域，用来核对界面细节。
#
# 用法: godot --headless --path runtime --script tools/crop-image.gd -- <in.png> <out.png> x,y,w,h [scale]

extends SceneTree


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		print("用法: -- <in.png> <out.png> x,y,w,h [scale]")
		quit(1)
		return
	var img := Image.load_from_file(a[0])
	if img == null:
		print("读不到 " + a[0])
		quit(1)
		return
	var p := a[2].split(",")
	var region := Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
	region = region.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var scale := float(a[3]) if a.size() > 3 else 2.0

	var crop := img.get_region(region)
	crop.resize(int(crop.get_width() * scale), int(crop.get_height() * scale), Image.INTERPOLATE_NEAREST)
	crop.save_png(a[1])
	print("已裁剪 %s -> %s (%d x %d)" % [a[0], a[1], crop.get_width(), crop.get_height()])
	quit(0)
