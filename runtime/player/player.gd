# 播放器：加载一个 .ee 项目、把它跑起来。
#
# 结构：
#   Player (Control，铺满窗口)
#    ├── SubViewportContainer（拉伸）
#    │    └── SubViewport (480x360)      ← 舞台，逻辑分辨率与 Scratch 一致
#    │         └── Stage (Node2D, 位于中心)
#    │              └── 各个角色节点
#    └── CanvasLayer                      ← 变量监视器
#
# 舞台上用的坐标永远是 Scratch 约定（中心原点、y 向上）；
# 只有 GodotBridge 在写节点时做一次换算。所以积木侧完全不用知道 Godot 的坐标系。
extends Control

const Registry = preload("res://ee/registry.gd")
const Project = preload("res://ee/project.gd")
const Compiler = preload("res://ee/compiler.gd")
const Runtime = preload("res://ee/runtime.gd")
const GodotBridge = preload("res://ee/bridge/godot_bridge.gd")
const Values = preload("res://ee/values.gd")

const DEFAULT_PROJECT := "res://tests/demo.ee.json"

var project_path := DEFAULT_PROJECT
var viewport: SubViewport = null
var stage_root: Node2D = null
var monitor_layer: CanvasLayer = null
var bridge = null
var runtime = null

var _stage_size := Vector2(480, 360)
var _elapsed := 0.0
var _reported_warnings := 0
var _debug := false
var _hud: Label = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--debug":
			_debug = true
			continue
		if not a.begins_with("--"):
			project_path = a

	_build_scene()
	var ok := _load_project()
	if ok:
		print("[player] 项目已启动：" + project_path)
		print("[player] 按 ESC 退出")
	else:
		_show_hud("加载失败：" + project_path + "\n请看控制台输出")


# ---------------------------------------------------------------- 场景

func _build_scene() -> void:
	var stage_size := _load_stage_size()

	# 窗口按舞台的整数倍放大，保证像素对齐
	var scale_factor := 2
	get_window().size = Vector2i(int(stage_size.x) * scale_factor, int(stage_size.y) * scale_factor)
	get_window().title = "Easy Engine — " + project_path.get_file()
	# 整数倍放大要配最近邻采样，否则像素画会糊
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 舞台根节点直接挂在窗口画布上，靠 scale 放大。
	#
	# 为什么不用 SubViewport + SubViewportContainer：那一层会自己改 SubViewport 的尺寸
	# （stretch 打开时是"容器尺寸 / stretch_shrink"），多一层换算就多一处能错，
	# 对它做居中布局也容易出问题。用缩放根节点效果等价且更好懂：
	# 积木与桥里用的始终是 480x360 的 Scratch 坐标，只有这一处乘上放大倍数。
	stage_root = Node2D.new()
	stage_root.name = "Stage"
	stage_root.scale = Vector2(scale_factor, scale_factor)
	stage_root.position = stage_size * 0.5 * scale_factor
	add_child(stage_root)

	monitor_layer = CanvasLayer.new()
	monitor_layer.name = "Monitors"
	add_child(monitor_layer)
	var vbox := VBoxContainer.new()
	vbox.name = "List"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	vbox.position = Vector2(12, 12)
	monitor_layer.add_child(vbox)

	_hud = Label.new()
	_hud.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hud.add_theme_constant_override("outline_size", 6)
	_hud.position = Vector2(12, 320)
	monitor_layer.add_child(_hud)


func _load_stage_size() -> Vector2:
	# 先粗略读一次 stage.size，好把窗口尺寸定对
	var fa := FileAccess.open(project_path, FileAccess.READ)
	if fa == null:
		return Vector2(480, 360)
	var d: Variant = JSON.parse_string(fa.get_as_text())
	fa.close()
	if typeof(d) == TYPE_DICTIONARY and d.has("stage"):
		var s: Array = (d["stage"] as Dictionary).get("size", [480, 360])
		return Vector2(float(s[0]), float(s[1]))
	return Vector2(480, 360)


# ---------------------------------------------------------------- 加载与运行

func _load_project() -> bool:
	var reg = Registry.new()
	reg.load_defs("res://ee/defs", [])
	if reg.errors().size() > 0:
		for e in reg.errors():
			push_error("[defs] " + str(e))
		return false

	var prj = Project.new()
	if not prj.load_file(project_path):
		for p in prj.problems:
			print("  [" + str(p["level"]) + "] " + str(p["message"]))
		return false

	var c = Compiler.new()
	c.registry = reg
	var ir: Dictionary = c.compile(prj)
	if c.errors().size() > 0:
		for p in c.problems:
			print("  [" + str(p["level"]) + "] " + str(p["message"]) + "  @ " + str(p["where"]))
		return false
	for p in c.warnings():
		print("  [警告] " + str(p["message"]))

	bridge = GodotBridge.new()
	bridge.stage_root = stage_root
	bridge.monitor_root = monitor_layer.get_node("List")
	bridge.asset_base = project_path.get_base_dir() + "/"

	runtime = Runtime.new()
	runtime.setup(reg, bridge)
	if runtime.errors.size() > 0:
		for e in runtime.errors:
			push_error("[runtime] " + str(e))
		return false

	runtime.load_ir(ir)
	_place_background(ir)
	runtime.green_flag()
	return true


func _place_background(ir: Dictionary) -> void:
	var bg_path := str((ir.get("stage", {}) as Dictionary).get("background", ""))
	if bg_path.is_empty():
		return
	# 同样回退到"直接读文件"：项目素材不走引擎的导入流程
	var full: String = bridge._resolve_asset(bg_path)
	var tex: Texture2D = null
	if ResourceLoader.exists(full):
		var res: Resource = load(full)
		if res is Texture2D:
			tex = res
	if tex == null:
		var img := Image.new()
		if img.load(full) == OK:
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		print("[player] 背景图加载失败：" + full)
		return
	var s := Sprite2D.new()
	s.name = "Background"
	s.texture = tex
	s.centered = true
	stage_root.add_child(s)
	stage_root.move_child(s, 0)


# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	if runtime == null:
		return
	_elapsed += delta
	runtime.step(delta)
	if bridge != null:
		bridge.refresh_monitors()
		# 桥的告警（素材找不到、代码块编译失败…）第一次出现就打印，避免被静默吞掉
		if bridge.warnings.size() > _reported_warnings:
			for i in range(_reported_warnings, bridge.warnings.size()):
				print("[bridge] " + str(bridge.warnings[i]))
			_reported_warnings = bridge.warnings.size()
	if _hud != null:
		_hud.text = "帧 %d   线程 %d   目标 %d" % [
			runtime.frame, runtime.live_thread_count(), runtime.targets.size()]
	if _debug and runtime.frame % 60 == 0:
		_dump_debug()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
	# 舞台尺寸变了（窗口被拉伸）时保持比例
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		pass


func _show_hud(text: String) -> void:
	if _hud != null:
		_hud.text = text
	print("[player] " + text)


# 排查用：把每个角色的位置、包围盒、命中判定打出来
func _dump_debug() -> void:
	print("---- 帧 %d ----" % runtime.frame)
	for t in runtime.targets:
		var p: Vector2 = bridge.get_position(t)
		var s: Vector2 = bridge.get_size(t)
		var node_p := Vector2.ZERO
		if t.node is Node2D:
			node_p = (t.node as Node2D).position
		print("  %-12s scratch=(%.1f, %.1f) size=(%.1f, %.1f) godot=(%.1f, %.1f) 分数=%s" % [
			t.id, p.x, p.y, s.x, s.y, node_p.x, node_p.y, str(runtime.get_var("分数", "auto", null))])
	print("  触摸判定 = %s" % str(bridge.is_touching(runtime.targets_by_id.get("Apple"), "Basket")))
