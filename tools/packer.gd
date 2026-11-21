# 把当前项目打进一个 .pck。
#
# 用法（由 tools/export-game.ps1 调用）：
#   godot --headless --path <项目> --script res://../packer.gd -- --out D:/xxx/Game.pck
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := ""
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]

	if out_path.is_empty():
		push_error("packer: 缺少 --out")
		quit(1)
		return

	var root := ProjectSettings.globalize_path("res://")
	var files: Array[String] = []
	_collect(root, root, files)

	var pck := PCKPacker.new()
	var err := pck.pck_start(out_path)
	if err != OK:
		push_error("packer: 无法创建 %s（错误码 %d）" % [out_path, err])
		quit(1)
		return

	for rel in files:
		var abs_path := root.path_join(rel)
		var inside := "res://" + rel.replace("\\", "/")
		var add_err := pck.add_file(inside, abs_path)
		if add_err != OK:
			push_error("packer: 加入失败 %s（错误码 %d）" % [inside, add_err])

	pck.flush()
	print("PACKER_OK files=%d out=%s" % [files.size(), out_path])
	quit(0)


func _collect(root: String, dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for name in d.get_files():
		# .import 是编辑器生成的，运行时用 .godot/imported 里的结果；
		# 我们这套积木项目基本是纯文本资源，跳过它没问题。
		if name.ends_with(".import") or name.ends_with(".uid"):
			continue
		var abs_path := dir.path_join(name)
		out.append(abs_path.trim_prefix(root).trim_prefix("/").trim_prefix("\\"))
	for sub in d.get_directories():
		if sub == ".godot" or sub.begins_with("."):
			continue
		_collect(root, dir.path_join(sub), out)
