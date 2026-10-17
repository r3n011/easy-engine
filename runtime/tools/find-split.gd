# 分析一张图片的"行墨迹分布"，找出上下两块图形之间的空白带。
# 用于把 logo 的图标与文字自动分开：这是按实际像素算的，不受路径重叠影响。
#
# 用法:
#   godot --headless --path runtime --script tools/find-split.gd -- <png> [白底阈值]

extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1:
		print("用法: -- <png> [threshold]")
		quit(1)
		return
	var path := args[0]
	var thresh := float(args[1]) if args.size() > 1 else 0.92

	var img := Image.load_from_file(path)
	if img == null:
		print("读不到图片: " + path)
		quit(1)
		return

	var w := img.get_width()
	var h := img.get_height()
	var rows := PackedInt32Array()
	rows.resize(h)
	for y in h:
		var ink := 0
		for x in w:
			var c := img.get_pixel(x, y)
			# 认为"接近白"的就是背景
			if c.r < thresh or c.g < thresh or c.b < thresh or c.a < 0.5:
				ink += 1
		rows[y] = ink

	print("图片 %d x %d" % [w, h])

	# 找出所有完全空白的行，取最长的一段（且上下都要有内容）
	var best_len := 0
	var best_mid := h / 2
	var start := -1
	for y in h:
		if rows[y] == 0:
			if start < 0:
				start = y
		else:
			if start >= 0:
				var ln := y - start
				if ln > best_len and start > 2 and y < h - 2:
					best_len = ln
					best_mid = int((start + y) / 2)
				start = -1

	print("最长空白带 %d 行，切分线 y=%d" % [best_len, best_mid])

	# 上下两块的像素范围（含 x），供裁剪用
	var top := _block_bounds(img, w, rows, 0, best_mid)
	var bot := _block_bounds(img, w, rows, best_mid, h)
	print("上块 %s" % top)
	print("下块 %s" % bot)
	print("CUT=%d" % best_mid)
	quit(0)


# 给定行范围，求墨迹的矩形范围
func _block_bounds(img: Image, w: int, rows: PackedInt32Array, y0: int, y1: int) -> String:
	var minx := w
	var maxx := -1
	var miny := -1
	var maxy := -1
	for y in range(y0, y1):
		if rows[y] == 0:
			continue
		if miny < 0:
			miny = y
		maxy = y
		for x in w:
			var c := img.get_pixel(x, y)
			if c.r < 0.92 or c.g < 0.92 or c.b < 0.92 or c.a < 0.5:
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
	if maxx < 0:
		return "（空）"
	return "x=%d..%d  y=%d..%d  (%d x %d)" % [minx, maxx, miny, maxy, maxx - minx + 1, maxy - miny + 1]
