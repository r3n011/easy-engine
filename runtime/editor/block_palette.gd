# 积木调色板：左边一列分类，右边列出该类积木。
#
# 列表项按下就直接在画布上生成积木并进入拖拽状态，
# 于是"从调色板里拖出来"和"拖动已有积木"是同一套逻辑，不用写两遍。
extends Control

const BlockView = preload("res://editor/block_view.gd")

var defs
var canvas

var _cat_list: VBoxContainer
var _block_list: VBoxContainer
var _current_cat := ""


func setup(p_defs, p_canvas) -> void:
	defs = p_defs
	canvas = p_canvas


func _ready() -> void:
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 0)
	add_child(split)

	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(96, 0)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left)
	_cat_list = VBoxContainer.new()
	_cat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cat_list.add_theme_constant_override("separation", 2)
	left.add_child(_cat_list)

	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right)
	_block_list = VBoxContainer.new()
	_block_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_block_list.add_theme_constant_override("separation", 4)
	right.add_child(_block_list)


func refresh() -> void:
	if defs == null or _cat_list == null:
		return
	for c in _cat_list.get_children():
		c.queue_free()
	for cat in defs.categories:
		# 该分类下没有积木就跳过（比如只启用了核心扩展时物理分类是空的）
		if defs.by_category(str(cat["id"])).is_empty():
			continue
		var b := Button.new()
		b.text = str(cat["name"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 30)
		var col := Color.html(str(cat["color"]))
		b.add_theme_stylebox_override("normal", _cat_style(col, false))
		b.add_theme_stylebox_override("hover", _cat_style(col, true))
		b.add_theme_stylebox_override("pressed", _cat_style(col, true))
		b.add_theme_color_override("font_color", Color(0.06, 0.08, 0.12))
		b.pressed.connect(func(): show_category(str(cat["id"])))
		_cat_list.add_child(b)

	if _current_cat == "" and not defs.categories.is_empty():
		for cat in defs.categories:
			if not defs.by_category(str(cat["id"])).is_empty():
				show_category(str(cat["id"]))
				break
	else:
		show_category(_current_cat)


func _cat_style(col: Color, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col.lightened(0.1) if hover else col
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 6
	return sb


func show_category(cat: String) -> void:
	_current_cat = cat
	for c in _block_list.get_children():
		c.queue_free()
	for id in defs.by_category(cat):
		var d = defs.def(id)
		var item := _make_item(d)
		_block_list.add_child(item)


# 列表项：画成一个小积木的样子（同色圆角 + 文字），按下去就能拖出来
func _make_item(d: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 28)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = "  " + _plain_message(d)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", 12)
	var col: Color = d.get("color", Color.GRAY)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 6
	var hov := sb.duplicate()
	hov.bg_color = col.lightened(0.12)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1.0))
	btn.button_down.connect(func(): canvas.spawn_and_drag(str(d["id"])))
	btn.tooltip_text = str(d["id"])
	return btn


# 列表里显示的短标签：由段落拼出来（文本段照抄，槽位用「（）」占位）。
# 注意不能读 def.message —— 解析后的定义里没有这个字段，只在 raw 里。
const MAX_LABEL := 15

func _plain_message(d: Dictionary) -> String:
	var s := ""
	for seg in d.get("segments", []):
		match str(seg.get("kind", "")):
			"text":
				s += str(seg.get("text", ""))
			"field":
				if str(seg.get("ftype", "")) == "dropdown":
					s += "▾"
				else:
					s += "（）"
			"value":
				s += "（）"
	if s.length() > MAX_LABEL:
		s = s.substr(0, MAX_LABEL - 1) + "…"
	return s.strip_edges()
