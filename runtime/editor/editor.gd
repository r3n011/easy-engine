# Easy Engine 编辑器（原生 Godot 界面）。
#
# 一个程序、一个窗口：左边角色、中间积木画布 + 舞台、右边积木调色板。
# 舞台就是同一个场景里的一个 Node2D，**点运行就地跑起来**，
# 不需要另开进程，也不需要截图当前端预览。
#
# 与网页方案的区别：这里没有浏览器，没有第二套代码。
# 积木定义仍然只有一份（runtime/ee/defs/blocks.*.json），
# 编辑器拿它画积木，运行时拿它编译 IR。
extends Control

const Defs = preload("res://editor/block_defs.gd")
const CanvasScript = preload("res://editor/block_canvas.gd")
const PaletteScript = preload("res://editor/block_palette.gd")
const CodecScript = preload("res://editor/codec.gd")

const Registry = preload("res://ee/registry.gd")
const Project = preload("res://ee/project.gd")
const Compiler = preload("res://ee/compiler.gd")
const Runtime = preload("res://ee/runtime.gd")
const GodotBridge = preload("res://ee/bridge/godot_bridge.gd")

const DEFAULT_PROJECT := "res://tests/demo.ee.json"

var defs
var canvas
var palette
var codec

var stage_root: Node2D
var stage_panel: Control
var monitor_box: VBoxContainer
var hud: Label

var project: Dictionary = {}
var project_path := DEFAULT_PROJECT
var active_node_id := ""

var runtime = null
var bridge = null
var running := false

var _node_list: VBoxContainer
var _detail: VBoxContainer
var _status_label: Label
var _title: Label


func _ready() -> void:
	var win := get_window()
	win.size = Vector2i(1320, 860)
	win.title = "Easy Engine 编辑器"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	defs = Defs.new()
	defs.load_defs([])

	_build_ui()
	palette.refresh()
	open_project(DEFAULT_PROJECT)

	# 启动就运行（方便验证与截图；也可以当"打开即预览"用）
	if OS.get_cmdline_user_args().has("--autorun"):
		run_project()


# ============================================================ 界面

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_topbar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	body.add_child(_build_left())

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 0)
	body.add_child(center)
	center.add_child(_build_canvas_area())
	center.add_child(_build_stage_area())

	body.add_child(_build_right())
	root.add_child(_build_status())


func _panel(color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	p.add_theme_stylebox_override("panel", sb)
	return p


func _build_topbar() -> Control:
	var bar := _panel(Color("#1a1f2a"))
	bar.custom_minimum_size = Vector2(0, 52)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bar.add_child(hb)

	var logo := TextureRect.new()
	var tex := _load_texture("res://brand/logo-icon.png")
	if tex != null:
		logo.texture = tex
	logo.custom_minimum_size = Vector2(34, 34)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hb.add_child(logo)

	var name := Label.new()
	name.text = "Easy Engine"
	name.add_theme_font_size_override("font_size", 16)
	hb.add_child(name)

	hb.add_child(_spacer())

	var run := Button.new()
	run.text = "▶  运行"
	run.custom_minimum_size = Vector2(92, 34)
	run.add_theme_color_override("font_color", Color(1, 1, 1))
	var run_sb := StyleBoxFlat.new()
	run_sb.bg_color = Color("#0f7fd4")
	run_sb.set_corner_radius_all(6)
	run.add_theme_stylebox_override("normal", run_sb)
	run.add_theme_stylebox_override("hover", run_sb)
	run.pressed.connect(run_project)
	hb.add_child(run)

	var stop := Button.new()
	stop.text = "■  停止"
	stop.custom_minimum_size = Vector2(92, 34)
	stop.pressed.connect(stop_project)
	hb.add_child(stop)

	hb.add_child(_spacer())

	_title = Label.new()
	_title.add_theme_color_override("font_color", Color("#8d99ad"))
	hb.add_child(_title)

	return bar


func _build_left() -> Control:
	var wrap := _panel(Color("#1a1f2a"))
	wrap.custom_minimum_size = Vector2(210, 0)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	wrap.add_child(vb)

	var title := Label.new()
	title.text = "  角色"
	title.add_theme_color_override("font_color", Color("#8d99ad"))
	vb.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_node_list = VBoxContainer.new()
	_node_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_node_list)

	var dscroll := ScrollContainer.new()
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(dscroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dscroll.add_child(_detail)

	return wrap


func _build_canvas_area() -> Control:
	var wrap := Control.new()
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL

	canvas = CanvasScript.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(canvas)
	canvas.setup(defs)

	codec = CodecScript.new()
	codec.setup(canvas)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1e2430")
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", sb)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(bg)
	wrap.move_child(bg, 0)

	return wrap


func _build_stage_area() -> Control:
	var outer := _panel(Color("#151a24"))
	outer.custom_minimum_size = Vector2(0, 400)

	var vb := VBoxContainer.new()
	outer.add_child(vb)

	var head := Label.new()
	head.text = "  舞台（就在这个窗口里跑）"
	head.add_theme_color_override("font_color", Color("#8d99ad"))
	vb.add_child(head)

	# 舞台用"面板 + 裁剪 + 缩放根节点"，不用 SubViewport：
	# 结构简单，而且鼠标位置天然正确（不必额外转发事件）。
	stage_panel = Control.new()
	stage_panel.clip_contents = true
	stage_panel.custom_minimum_size = Vector2(480, 360)
	stage_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(stage_panel)

	var backdrop := ColorRect.new()
	backdrop.color = Color("#0b0e14")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_panel.add_child(backdrop)

	stage_root = Node2D.new()
	stage_root.name = "Stage"
	stage_root.scale = Vector2(1, 1)
	stage_root.position = Vector2(240, 180)
	stage_panel.add_child(stage_root)

	var mlayer := Control.new()
	mlayer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mlayer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_panel.add_child(mlayer)
	monitor_box = VBoxContainer.new()
	monitor_box.position = Vector2(8, 8)
	mlayer.add_child(monitor_box)
	hud = Label.new()
	hud.position = Vector2(8, 334)
	hud.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("outline_size", 5)
	mlayer.add_child(hud)

	return outer


func _build_right() -> Control:
	var wrap := _panel(Color("#151a24"))
	wrap.custom_minimum_size = Vector2(320, 0)
	palette = PaletteScript.new()
	palette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(palette)
	palette.setup(defs, canvas)
	return wrap


func _build_status() -> Control:
	var bar := _panel(Color("#222836"))
	bar.custom_minimum_size = Vector2(0, 26)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	bar.add_child(hb)
	_status_label = Label.new()
	_status_label.text = "就绪"
	_status_label.add_theme_color_override("font_color", Color("#8d99ad"))
	_status_label.add_theme_font_size_override("font_size", 12)
	hb.add_child(_status_label)
	hb.add_child(_spacer())
	var info := Label.new()
	info.text = "积木 %d 个 · 分类 %d 个" % [defs.blocks.size(), defs.categories.size()]
	info.add_theme_color_override("font_color", Color("#5f6b80"))
	info.add_theme_font_size_override("font_size", 12)
	hb.add_child(info)
	return bar


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


# 编辑器项目里的图片不经过 Godot 的导入流程，load() 拿不到，
# 所以统一走"先试资源加载、再直接读文件"。
func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null


func status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


# ============================================================ 项目

func open_project(path: String) -> void:
	var prj = Project.new()
	var abs_path := path
	if not prj.load_file(abs_path):
		status("打开失败：" + path)
		for p in prj.problems:
			print("  [" + str(p["level"]) + "] " + str(p["message"]))
		return
	project = prj.data
	project_path = path
	_title.text = "  " + str(project.get("name", "")) + "  ·  " + path
	active_node_id = ""
	if not project.get("nodes", []).is_empty():
		active_node_id = str(project["nodes"][0].get("id", ""))
	_render_nodes()
	_load_active_node()
	status("已打开 " + path)


func _render_nodes() -> void:
	for c in _node_list.get_children():
		c.queue_free()
	for n in project.get("nodes", []):
		var b := Button.new()
		b.text = "  " + str(n.get("name", n.get("id", "")))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 30)
		b.set_meta("node_id", str(n.get("id", "")))
		b.pressed.connect(func(): _select_node(str(n.get("id", ""))))
		_node_list.add_child(b)
	_render_detail()


func _render_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	var n := _find_node(active_node_id)
	if n.is_empty():
		return
	var lines := [
		["id", str(n.get("id", ""))],
		["模板", str(n.get("template", ""))],
		["造型", str((n.get("costumes", []) as Array).size()) + " 个"],
	]
	var t: Dictionary = n.get("transform", {})
	var pos: Array = t.get("position", [0, 0])
	lines.append(["位置", "%s, %s" % [pos[0], pos[1]]])
	for l in lines:
		var row := Label.new()
		row.text = "  %s：%s" % [l[0], l[1]]
		row.add_theme_color_override("font_color", Color("#9aa7bd"))
		row.add_theme_font_size_override("font_size", 12)
		_detail.add_child(row)


func _find_node(id: String) -> Dictionary:
	for n in project.get("nodes", []):
		if str(n.get("id", "")) == id:
			return n
	return {}


func _select_node(id: String) -> void:
	if id == active_node_id:
		return
	_sync_canvas_to_project()
	active_node_id = id
	_load_active_node()
	_render_detail()


func _load_active_node() -> void:
	var n := _find_node(active_node_id)
	codec.from_scripts(n.get("scripts", []) if not n.is_empty() else [])
	status("当前角色：" + str(n.get("name", "")))


func _sync_canvas_to_project() -> void:
	if project.is_empty() or active_node_id == "":
		return
	var scripts: Array = codec.to_scripts()
	for n in project.get("nodes", []):
		if str(n.get("id", "")) == active_node_id:
			n["scripts"] = scripts
			return


# ============================================================ 运行

func run_project() -> void:
	_sync_canvas_to_project()
	stop_project()

	var reg = Registry.new()
	reg.load_defs("res://ee/defs", [])
	if reg.errors().size() > 0:
		status("积木定义有问题：" + str(reg.errors()[0]))
		return

	var prj = Project.new()
	if not prj.load_text(JSON.stringify(project)):
		status("项目无法解析")
		return
	var c = Compiler.new()
	c.registry = reg
	var ir: Dictionary = c.compile(prj)
	if c.errors().size() > 0:
		status("编译失败：" + str(c.errors()[0]["message"]))
		return

	_clear_stage()
	bridge = GodotBridge.new()
	bridge.stage_root = stage_root
	bridge.monitor_root = monitor_box
	bridge.asset_base = project_path.get_base_dir() + "/"

	runtime = Runtime.new()
	runtime.setup(reg, bridge)
	if runtime.errors.size() > 0:
		status("运行时启动失败：" + str(runtime.errors[0]))
		return
	runtime.load_ir(ir)
	_place_background(ir)
	runtime.green_flag()
	running = true
	status("运行中：%d 个目标，%d 个脚本" % [ir.get("nodes", []).size(), _script_count(ir)])


func _script_count(ir: Dictionary) -> int:
	var n := 0
	for node in ir.get("nodes", []):
		n += (node.get("scripts", []) as Array).size()
	return n


func stop_project() -> void:
	if runtime != null:
		runtime.stop_all()
		runtime.dispose()
		runtime = null
	running = false
	for c in monitor_box.get_children():
		c.queue_free()


func _clear_stage() -> void:
	for c in stage_root.get_children():
		c.queue_free()


func _place_background(ir: Dictionary) -> void:
	var bg := str((ir.get("stage", {}) as Dictionary).get("background", ""))
	if bg.is_empty():
		return
	var full: String = bridge._resolve_asset(bg)
	var tex := _load_texture(full)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.name = "Background"
	s.texture = tex
	stage_root.add_child(s)
	stage_root.move_child(s, 0)


func _process(delta: float) -> void:
	if runtime == null:
		return
	runtime.step(delta)
	bridge.refresh_monitors()
	if hud != null:
		hud.text = "帧 %d  线程 %d  目标 %d" % [
			runtime.frame, runtime.live_thread_count(), runtime.targets.size()]


func _input(event: InputEvent) -> void:
	# ESC 退出（编辑器里先停游戏）
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		stop_project()
		get_tree().quit()
