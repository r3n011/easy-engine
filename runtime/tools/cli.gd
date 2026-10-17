# M1 验收用命令行工具。
#
# 用法（注意 -- 之后的参数才会传给脚本）：
#   godot --headless --path runtime --script tools/cli.gd -- defs
#   godot --headless --path runtime --script tools/cli.gd -- check  tests/sample.ee.json
#   godot --headless --path runtime --script tools/cli.gd -- compile tests/sample.ee.json [--ext ee.physics2d] [--out out.json]
#   godot --headless --path runtime --script tools/cli.gd -- regress
extends SceneTree

const Registry = preload("res://ee/registry.gd")
const Project = preload("res://ee/project.gd")
const Compiler = preload("res://ee/compiler.gd")
const Version = preload("res://ee/version.gd")
const Runtime = preload("res://ee/runtime.gd")
const NodeBridge = preload("res://ee/bridge/node_bridge.gd")
const Values = preload("res://ee/values.gd")

const DEFS_DIR := "res://ee/defs"
const SAMPLE := "res://tests/sample.ee.json"
const BASELINE := "res://tests/sample.expected-ir.json"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var cmd := args[0] if args.size() > 0 else "help"
	var files: Array = []
	var exts: Array = []
	var out_path := ""
	var frames := 120

	var i := 1
	while i < args.size():
		match args[i]:
			"--ext":
				i += 1
				if i < args.size():
					exts.append(args[i])
			"--out":
				i += 1
				if i < args.size():
					out_path = args[i]
			"--frames":
				i += 1
				if i < args.size():
					frames = args[i].to_int()
			_:
				files.append(args[i])
		i += 1

	var code := 0
	match cmd:
		"defs":
			code = _cmd_defs(exts)
		"check":
			code = _cmd_check(files, exts)
		"compile":
			code = _cmd_compile(files, exts, out_path)
		"run":
			code = _cmd_run(files, exts, frames, out_path)
		"regress":
			code = _cmd_regress(exts)
		_:
			_usage()
	quit(code)


func _usage() -> void:
	print("""
Easy Engine M1 验收工具

  defs                 列出注册表（扩展 / 积木 / op）并报告定义问题
  check  <file.ee>     只校验，不产出 IR
  compile <file.ee>    编译并输出 IR      [--ext <扩展id>] [--out <路径>]
  run    <file.ee>     编译后真正跑起来    [--frames N] [--ext <扩展id>]
  regress              编译示例项目并与基准逐字比对

选项:
  --ext <id>   启用某个扩展（可多次）。不指定 = 全部启用。
  --out <路径> 把 IR 写入文件（compile 用）
  --frames <N> 运行多少帧（run 用，默认 120）
""")


func _make_registry(exts: Array):
	var reg = Registry.new()
	reg.load_defs(DEFS_DIR, exts)
	return reg


func _print_problems(problems: Array, title: String) -> int:
	var errs := 0
	var warns := 0
	for p in problems:
		var tag := "错误" if p["level"] == "error" else ("警告" if p["level"] == "warn" else "信息")
		if p["level"] == "error":
			errs += 1
		elif p["level"] == "warn":
			warns += 1
		var w := ("  @ " + str(p["where"])) if str(p.get("where", "")) != "" else ""
		print("  [%s] %-18s %s%s" % [tag, p["code"], p["message"], w])
	if errs == 0 and warns == 0:
		print("  （无问题）")
	return errs


func _cmd_defs(exts: Array) -> int:
	var reg = _make_registry(exts)
	print("== 注册表 ==")
	print("  " + reg.summary())
	print("")
	print("== 扩展 ==")
	for eid in reg.extensions:
		var e: Dictionary = reg.extensions[eid]
		print("  %-18s v%d  积木 %d 个，op %d 个%s" % [
			eid, int(e["version"]), e["blocks"].size(), e["ops"].size(),
			"" if reg.is_ext_enabled(eid) else "  [未启用]"])
	print("")
	print("== 定义问题 ==")
	var errs := _print_problems(reg.problems, "defs")
	return 1 if errs > 0 else 0


func _load_project(path: String):
	var prj = Project.new()
	if not prj.load_file(path):
		print("== 项目加载失败: %s ==" % path)
		_print_problems(prj.problems, "project")
		return null
	return prj


func _cmd_check(files: Array, exts: Array) -> int:
	if files.is_empty():
		print("用法: check <file.ee>")
		return 2
	var reg = _make_registry(exts)
	var rc := 0
	for f in files:
		print("== 校验 %s ==" % f)
		var prj = _load_project(f)
		if prj == null:
			rc = 1
			continue
		if prj.migrated_from != Version.FORMAT_VERSION:
			print("  格式版本: 文件 %d -> 当前 %d" % [prj.migrated_from, Version.FORMAT_VERSION])
		_print_problems(prj.problems, "project")

		var c = Compiler.new()
		c.registry = reg
		c.compile(prj)
		print("  -- 编译检查 --")
		if _print_problems(c.problems, "compile") > 0:
			rc = 1
		print("  节点 %d 个，脚本 %d 个" % [prj.nodes().size(), _count_scripts(prj)])
	return rc


func _count_scripts(prj) -> int:
	var n := 0
	for node in prj.nodes():
		n += node.get("scripts", []).size()
	return n


func _cmd_compile(files: Array, exts: Array, out_path: String) -> int:
	if files.is_empty():
		print("用法: compile <file.ee> [--ext <id>] [--out <路径>]")
		return 2
	var reg = _make_registry(exts)
	var path: String = files[0]

	var prj = _load_project(path)
	if prj == null:
		return 1

	var c = Compiler.new()
	c.registry = reg
	var ir := c.compile(prj)

	if c.errors().size() > 0:
		print("== 编译失败 ==")
		_print_problems(c.problems, "compile")
		return 1

	if c.warnings().size() > 0:
		print("== 警告 ==")
		_print_problems(c.problems, "compile")

	var text := JSON.stringify(ir, "  ", true)
	if out_path.is_empty():
		print(text)
	else:
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		if fa == null:
			print("无法写入 " + out_path)
			return 1
		fa.store_string(text + "\n")
		fa.close()
		print("已写入 " + out_path)
	return 0


# 编译并真正跑起来。这是 M2 的端到端验证：.ee → IR → 调度器执行。
func _cmd_run(files: Array, exts: Array, frames: int, out_path: String) -> int:
	if files.is_empty():
		print("用法: run <file.ee> [--frames N] [--ext <id>]")
		return 2
	var reg = _make_registry(exts)
	var prj = _load_project(files[0])
	if prj == null:
		return 1

	var c = Compiler.new()
	c.registry = reg
	var ir := c.compile(prj)
	if c.errors().size() > 0:
		print("== 编译失败 ==")
		_print_problems(c.problems, "compile")
		return 1
	if not out_path.is_empty():
		var fo := FileAccess.open(out_path, FileAccess.WRITE)
		if fo != null:
			fo.store_string(JSON.stringify(ir, "  ", true) + "\n")
			fo.close()
			print("IR 已写入 " + out_path)

	var bridge = NodeBridge.new()
	var rt = Runtime.new()
	rt.setup(reg, bridge)
	if rt.errors.size() > 0:
		print("== 运行时启动失败 ==")
		for e in rt.errors:
			print("  " + str(e))
		return 1

	rt.load_ir(ir)
	print("== 运行 %d 帧 ==" % frames)
	print("  启动前：" + rt.describe_state())

	var started = rt.green_flag()
	print("  绿旗触发了 %d 个脚本" % started.size())
	if started.is_empty():
		print("  （没有「当绿旗被点击」的脚本，什么都不会发生）")

	rt.run_frames(frames, 1.0 / 60.0)

	print("  运行后：" + rt.describe_state())
	print("")
	print("== 全局变量 ==")
	var names: Array = rt.globals.keys()
	names.sort()
	for n in names:
		print("  %-16s = %s" % [n, Values.to_string_value(rt.globals[n])])
	if not rt.global_lists.is_empty():
		print("== 全局列表 ==")
		for n in rt.global_lists:
			print("  %-16s = %s" % [n, JSON.stringify(rt.global_lists[n])])
	print("")
	print("== 目标状态 ==")
	for t in rt.targets:
		var pos: Vector2 = bridge.get_position(t)
		print("  %-14s 位置 (%.1f, %.1f)  方向 %.1f  造型 %s%s" % [
			t.describe(), pos.x, pos.y, float(t.state.get("direction", 90.0)),
			str(t.state.get("costume", "")), "  隐藏" if not bool(t.state.get("visible", true)) else ""])

	if rt.warnings.size() > 0 or bridge.warnings.size() > 0:
		print("")
		print("== 告警 ==")
		for w in rt.warnings:
			print("  " + str(w))
		for w in bridge.warnings:
			print("  " + str(w))
	if rt.errors.size() > 0:
		print("")
		print("== 运行时错误 ==")
		for e in rt.errors:
			print("  " + str(e))
		rt.dispose()
		return 1

	rt.dispose()
	return 0


func _cmd_regress(exts: Array) -> int:
	if not FileAccess.file_exists(BASELINE):
		print("缺少基准文件 " + BASELINE)
		print("先运行: compile %s --out %s" % [SAMPLE, BASELINE])
		return 1
	var reg = _make_registry(exts)
	var prj = _load_project(SAMPLE)
	if prj == null:
		return 1
	var c = Compiler.new()
	c.registry = reg
	var ir := c.compile(prj)
	if c.errors().size() > 0:
		print("== 编译失败 ==")
		_print_problems(c.problems, "compile")
		return 1

	var got := JSON.stringify(ir, "  ", true)
	var fa := FileAccess.open(BASELINE, FileAccess.READ)
	var want := fa.get_as_text().strip_edges()
	fa.close()

	if got == want:
		print("回归通过：IR 与基准一致（%d 字节）" % got.length())
		return 0

	print("回归失败：IR 与基准不一致")
	_show_diff(want.split("\n"), got.split("\n"))
	return 1


func _show_diff(a: PackedStringArray, b: PackedStringArray) -> void:
	var n: int = max(a.size(), b.size())
	var shown := 0
	for i in n:
		var la := a[i] if i < a.size() else "<缺失>"
		var lb := b[i] if i < b.size() else "<缺失>"
		if la != lb:
			print("  第 %d 行:" % (i + 1))
			print("    基准: " + la)
			print("    实际: " + lb)
			shown += 1
			if shown >= 12:
				print("  ...（只显示前 12 处差异）")
				break
