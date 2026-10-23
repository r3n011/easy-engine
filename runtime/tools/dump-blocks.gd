# 离屏检查：加载项目 → 生成积木 → 打印实际的父子关系与坐标。
# 用来排查"画布上积木位置不对"这类问题，比看截图快。
#
# 用法: godot --headless --path runtime --script tools/dump-blocks.gd -- [项目路径] [节点序号]
extends SceneTree

const Defs = preload("res://editor/block_defs.gd")
const CanvasScript = preload("res://editor/block_canvas.gd")
const CodecScript = preload("res://editor/codec.gd")
const Project = preload("res://ee/project.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "res://tests/demo.ee.json"
	var node_idx := int(args[1]) if args.size() > 1 else 0

	var defs = Defs.new()
	defs.load_defs([])
	print("积木定义 %d 个，分类 %d 个" % [defs.blocks.size(), defs.categories.size()])

	var host := Control.new()
	get_root().add_child(host)

	var canvas = CanvasScript.new()
	host.add_child(canvas)
	canvas.setup(defs)

	var codec = CodecScript.new()
	codec.setup(canvas)

	var prj = Project.new()
	if not prj.load_file(path):
		print("加载失败：" + path)
		quit(1)
		return
	var nodes: Array = prj.data.get("nodes", [])
	if node_idx >= nodes.size():
		print("节点序号越界")
		quit(1)
		return
	var node: Dictionary = nodes[node_idx]
	print("节点 %s 有 %d 个脚本" % [node.get("id", "?"), (node.get("scripts", []) as Array).size()])

	codec.from_scripts(node.get("scripts", []))

	print("顶层积木 %d 个：" % canvas.roots.size())
	for r in canvas.roots:
		_dump(r, 0)
	print("--- 再导出一次，核对结构化结果 ---")
	var out := codec.to_scripts()
	print(JSON.stringify(out, "  ", false).substr(0, 1200))
	quit(0)


func _dump(b, depth: int) -> void:
	var pad := ""
	for i in depth:
		pad += "  "
	print("%s· %s  pos=%s size=%s  attached=%s" % [
		pad, b.block_id, str(b.position), str(b.size), b.attached_as])
	for name in b.inputs:
		print("%s  [值槽 %s]" % [pad, name])
		_dump(b.inputs[name], depth + 1)
	for name in b.stmt_slots:
		var list: Array = b.stmt_slots[name]
		print("%s  [语句槽 %s] %d 个" % [pad, name, list.size()])
		for c in list:
			_dump(c, depth + 1)
	if b.next_block != null:
		print("%s  [下一个]" % pad)
		_dump(b.next_block, depth + 1)
