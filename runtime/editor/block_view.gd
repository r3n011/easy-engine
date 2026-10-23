# 单个积木的绘制与布局。
#
# 形状照 Scratch：
#   帽子  圆角矩形 + 顶部拱形，下边有凸榫
#   堆叠  圆角矩形，上边有凹口、下边有凸榫（C 形积木还带一个缩进的语句区）
#   报告  胶囊形（圆角 = 高度一半）
#   布尔  六边形
#
# 交互不由本类处理：**拖拽与吸附全在 canvas 里做**，
# 积木只负责"我长在哪、我的连接点在哪"。这样逻辑只有一处，不用到处转发事件。
# 只有字段（下拉/输入框）自己吃鼠标事件，因为它们是真正可编辑的控件。
extends Control

const ROW_H := 26.0
const PAD_X := 10.0
const PAD_Y := 5.0
const GAP := 6.0
const MIN_SOCKET_W := 34.0
const MAX_W := 330.0
const NOTCH_X := 18.0
const NOTCH_W := 14.0
const NOTCH_H := 4.0
const STMT_INDENT := 14.0
const STMT_MIN_H := 20.0
const FONT_SIZE := 13

var def := {}
var block_id := ""

# 数据
var fields := {}          # name -> 值（下拉/输入框里的字面量）
var inputs := {}          # name -> BlockView（塞进值槽的报告积木）
var stmt_slots := {}      # name -> Array[BlockView]（语句槽里的积木串）
var next_block = null     # 同一串里的下一个积木

# 连接关系（供 canvas 吸附/摘除用）
var attached_as := ""     # "" | "free" | "next" | "stmt" | "value"
var attached_owner = null # 被接在谁身上
var attached_slot := ""   # 接在哪个槽

# 布局结果
var header_h := ROW_H
var body_w := 120.0
var body_h := ROW_H
var _text_draws := []     # [{text, pos}]
var _socket_rects := {}   # name -> Rect2
var _stmt_rects := {}     # name -> Rect2
var _value_pos := {}      # name -> Vector2（值槽中心，供吸附用）
var _field_controls := {} # name -> Control

var _font: Font
var _selected := false

signal changed   # 字段被改 / 子积木变化，通知 canvas 重新布局


func setup(p_def: Dictionary) -> void:
	def = p_def
	block_id = str(def.get("id", ""))
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_PASS   # 事件交给 canvas 统一处理
	_build_fields()


func _build_fields() -> void:
	for seg in def.get("segments", []):
		if seg["kind"] == "field":
			fields[seg["name"]] = _default_of(seg)
		elif seg["kind"] == "value":
			fields[seg["name"]] = _default_of(seg)
			stmt_slots.erase(seg["name"])
		elif seg["kind"] == "stmt":
			if not stmt_slots.has(seg["name"]):
				stmt_slots[seg["name"]] = []


func _default_of(seg: Dictionary) -> Variant:
	if seg.has("value"):
		return seg["value"]
	if seg["kind"] == "field" and not seg.get("options", []).is_empty():
		return seg["options"][0].get("value", "")
	return ""


func shape() -> String:
	return str(def.get("shape", "stack"))

func color() -> Color:
	return def.get("color", Color.GRAY)


# ============================================================ 布局

func relayout() -> void:
	# 先让子积木自己排好
	for name in inputs:
		inputs[name].relayout()
	for name in stmt_slots:
		for child in stmt_slots[name]:
			child.relayout()
	if next_block != null:
		next_block.relayout()   # 它是我下面的子节点，得先知道自己多高

	_text_draws.clear()
	_socket_rects.clear()
	_stmt_rects.clear()
	_value_pos.clear()

	var sh := shape()
	var x := PAD_X
	var y := PAD_Y
	var row_max := 0.0
	var stmt_list := []
	var active_fields := {}

	for seg in def.get("segments", []):
		var kind := str(seg["kind"])
		if kind == "stmt":
			stmt_list.append(seg["name"])
			continue

		var w := 0.0
		if kind == "text":
			w = _text_size(str(seg["text"])).x
		elif kind == "field":
			w = _field_width(seg)
		elif kind == "value":
			w = _value_width(seg)

		# 太长就换行（Scratch 也是这样折行的）
		if x > PAD_X and x + w > MAX_W and kind != "text":
			row_max = maxf(row_max, x)
			x = PAD_X + STMT_INDENT
			y += ROW_H

		if kind == "text":
			_text_draws.append({ "text": str(seg["text"]), "pos": Vector2(x, y + ROW_H * 0.5) })
			x += w + GAP
		elif kind == "field":
			var fname := str(seg["name"])
			_ensure_field(seg, Rect2(x, y + 2, w, ROW_H - 4))
			active_fields[fname] = true
			x += w + GAP
		elif kind == "value":
			var name := str(seg["name"])
			if inputs.has(name):
				var child: Control = inputs[name]
				child.position = Vector2(x, y + (ROW_H - child.body_h) * 0.5)
				x += child.body_w + GAP
			else:
				_socket_rects[name] = Rect2(x, y + 2, w, ROW_H - 4)
				_ensure_field(seg, Rect2(x, y + 2, w, ROW_H - 4))
				active_fields[name] = true
				x += w + GAP
			# 无论有没有塞进积木，都要留一个值槽连接点
			_value_pos[name] = Vector2(x - w - GAP + w * 0.5, y + ROW_H * 0.5)

	row_max = maxf(row_max, x)

	# 语句区（C 形积木的下半部分）
	if not stmt_list.is_empty():
		var inner_x := PAD_X + STMT_INDENT
		for name in stmt_list:
			var yy := y + ROW_H
			var list: Array = stmt_slots.get(name, [])
			var child_y := yy + STMT_MIN_H * 0.5 - ROW_H * 0.5
			var maxw := 0.0
			for child in list:
				child.position = Vector2(inner_x, child_y)
				child_y += child.body_h
				maxw = maxf(maxw, child.body_w)
			var slot_h := maxf(STMT_MIN_H, child_y - yy - (STMT_MIN_H * 0.5 - ROW_H * 0.5) + ROW_H * 0.5)
			_stmt_rects[name] = Rect2(inner_x, yy, maxf(row_max - inner_x, maxw + 4.0), slot_h)
			y += slot_h + 4.0
		body_w = maxf(row_max + PAD_X, PAD_X + STMT_INDENT + 60.0)
		header_h = ROW_H + PAD_Y
		body_h = y + PAD_Y
	else:
		body_w = maxf(row_max + PAD_X, 70.0)
		header_h = ROW_H + PAD_Y
		body_h = ROW_H + PAD_Y

	# 只清掉"这一轮不再需要"的字段控件（比如值槽里塞进了报告积木）。
	# 千万不能每轮重建：用户正在输入时被销毁会丢焦点与光标。
	for name in _field_controls.keys():
		if not active_fields.has(name):
			var c: Control = _field_controls[name]
			if is_instance_valid(c):
				c.queue_free()
			_field_controls.erase(name)

	size = Vector2(body_w, body_h)
	custom_minimum_size = size
	position_changed_children()
	queue_redraw()


func position_changed_children() -> void:
	# 让"我这一串"下面的积木跟着我动
	var b = next_block
	var yy := body_h
	while b != null:
		b.position = Vector2(0, yy)
		yy += b.body_h
		b = b.next_block


func total_stack_height() -> float:
	var h := body_h
	var b = next_block
	while b != null:
		h += b.body_h
		b = b.next_block
	return h


func _text_size(s: String) -> Vector2:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)


func _field_width(seg: Dictionary) -> float:
	var name := str(seg["name"])
	var ftype := str(seg.get("ftype", "text"))
	if ftype == "dropdown":
		var label := ""
		for o in seg.get("options", []):
			if str(o.get("value", "")) == str(fields.get(name, "")):
				label = str(o.get("label", o.get("value", "")))
		return maxf(48.0, _text_size(label).x + 22.0)
	var txt := str(fields.get(name, ""))
	return clampf(_text_size(txt).x + 18.0, 40.0, 190.0)


func _value_width(seg: Dictionary) -> float:
	var name := str(seg["name"])
	var vtype := str(seg.get("vtype", "any"))
	if inputs.has(name):
		return inputs[name].body_w
	var txt := str(fields.get(name, ""))
	var w := _text_size(txt).x + 18.0
	if vtype == "boolean":
		w = maxf(w, 40.0)
	elif vtype == "expression":
		w = maxf(w, 96.0)
	elif vtype == "code":
		w = maxf(w, 150.0)
	return clampf(w, MIN_SOCKET_W, 210.0)


# ============================================================ 字段控件

func _ensure_field(seg: Dictionary, rect: Rect2) -> void:
	var name := str(seg["name"])
	if _field_controls.has(name):
		var c: Control = _field_controls[name]
		if is_instance_valid(c):
			c.position = rect.position
			c.size = rect.size
			return
		_field_controls.erase(name)

	var ftype := str(seg.get("ftype", seg.get("vtype", "text")))
	var ctrl: Control
	if ftype == "dropdown":
		var ob := OptionButton.new()
		for i in seg.get("options", []).size():
			var o: Dictionary = seg["options"][i]
			ob.add_item(str(o.get("label", o.get("value", ""))), i)
			ob.set_item_metadata(i, o.get("value", ""))
		var idx := 0
		for i in seg.get("options", []).size():
			if str(seg["options"][i].get("value", "")) == str(fields.get(name, "")):
				idx = i
		ob.selected = idx
		_style_option(ob, rect.size.y)
		ob.item_selected.connect(func(i2): _on_field_changed(name, ob.get_item_metadata(i2)))
		ctrl = ob
	elif ftype == "boolean":
		var ob2 := OptionButton.new()
		ob2.add_item("真", 0); ob2.set_item_metadata(0, true)
		ob2.add_item("假", 1); ob2.set_item_metadata(1, false)
		ob2.selected = 0 if bool(fields.get(name, false)) else 1
		_style_option(ob2, rect.size.y)
		ob2.item_selected.connect(func(i2): _on_field_changed(name, ob2.get_item_metadata(i2)))
		ctrl = ob2
	else:
		var le := LineEdit.new()
		le.text = str(fields.get(name, ""))
		le.add_theme_font_size_override("font_size", FONT_SIZE - 1)
		le.add_theme_color_override("font_color", Color(0.12, 0.14, 0.2))
		le.add_theme_color_override("caret_color", Color(0.1, 0.1, 0.15))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.94)
		sb.set_corner_radius_all(int(rect.size.y * 0.5))
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		le.add_theme_stylebox_override("normal", sb)
		le.add_theme_stylebox_override("focus", sb)
		le.text_changed.connect(func(t2): _on_field_changed(name, t2))
		ctrl = le

	ctrl.position = rect.position
	ctrl.size = rect.size
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP   # 字段自己吃事件，别被 canvas 当成拖拽
	add_child(ctrl)
	_field_controls[name] = ctrl


func _style_option(ob: OptionButton, h: float) -> void:
	ob.add_theme_font_size_override("font_size", FONT_SIZE - 1)
	ob.add_theme_color_override("font_color", Color(0.12, 0.14, 0.2))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.94)
	sb.set_corner_radius_all(int(h * 0.5))
	sb.content_margin_left = 6
	sb.content_margin_right = 14
	ob.add_theme_stylebox_override("normal", sb)
	ob.add_theme_stylebox_override("hover", sb)
	ob.add_theme_stylebox_override("pressed", sb)
	ob.add_theme_stylebox_override("focus", sb)


func _on_field_changed(name: String, value: Variant) -> void:
	fields[name] = value
	changed.emit()


# ============================================================ 绘制

func _draw() -> void:
	var sh := shape()
	var col := color()
	var border := col.darkened(0.32)

	match sh:
		"reporter":
			_draw_pill(col, border)
		"boolean":
			_draw_hexagon(col, border)
		_:
			_draw_stack_body(col, border, sh == "hat")

	# 文字
	for t in _text_draws:
		var p: Vector2 = t["pos"]
		var sz := _text_size(str(t["text"]))
		draw_string(_font, p + Vector2(0, sz.y * 0.32), str(t["text"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1, 1, 1, 0.96))

	# 空的槽：画成"洞"，提示这里可以塞东西
	for name in _socket_rects:
		draw_socket(_socket_rects[name], col)

	# 语句槽的底
	for name in _stmt_rects:
		var r: Rect2 = _stmt_rects[name]
		draw_rect(Rect2(r.position, r.size), Color(0, 0, 0, 0.10), true)

	# 选中描边
	if _selected:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.35), false, 1.0)


func _draw_stack_body(col: Color, border: Color, is_hat: bool) -> void:
	var has_stmt := not _stmt_rects.is_empty()

	if has_stmt:
		_draw_c_shape(col, border)
	else:
		var radius := 5
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.border_color = border
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(radius)
		if is_hat:
			sb.corner_radius_top_left = 16
			sb.corner_radius_top_right = 16
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(NOTCH_X, 0, NOTCH_W, NOTCH_H), Color(0, 0, 0, 0.18), true)

	if is_hat:
		# 帽子顶部再描一个圆角，避免 C 形那里方头方脑
		var top := StyleBoxFlat.new()
		top.bg_color = col
		top.border_color = border
		top.set_border_width_all(1)
		top.corner_radius_top_left = 16
		top.corner_radius_top_right = 16
		top.corner_radius_bottom_left = 0
		top.corner_radius_bottom_right = 0
		draw_style_box(top, Rect2(Vector2.ZERO, Vector2(size.x, header_h)))

	# 底部凸榫（下一个积木接在这）
	if shape() == "stack":
		var tab := StyleBoxFlat.new()
		tab.bg_color = col
		tab.set_corner_radius_all(3)
		draw_style_box(tab, Rect2(NOTCH_X, size.y - 2, NOTCH_W, NOTCH_H + 2))


# C 形：上半条 + 左侧一条腿 + 下半条，中间让出语句区。
# Scratch 的「重复执行」「如果」都是这个形状。
func _draw_c_shape(col: Color, border: Color) -> void:
	var ix := PAD_X + STMT_INDENT          # 语句区左边界
	var bar := ROW_H * 0.72                # 下横条高度
	var h := size.y
	var pts := PackedVector2Array([
		Vector2(0, 0),
		Vector2(size.x, 0),
		Vector2(size.x, header_h),
		Vector2(ix, header_h),
		Vector2(ix, h - bar),
		Vector2(size.x, h - bar),
		Vector2(size.x, h),
		Vector2(0, h),
	])
	draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, border, 1.0, true)
	draw_rect(Rect2(NOTCH_X, 0, NOTCH_W, NOTCH_H), Color(0, 0, 0, 0.18), true)


func _draw_pill(col: Color, border: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(size.y * 0.5))
	draw_style_box(sb, Rect2(Vector2.ZERO, size))


func _draw_hexagon(col: Color, border: Color) -> void:
	var h := size.y
	var nub := h * 0.34
	var pts := PackedVector2Array([
		Vector2(nub, 0), Vector2(size.x - nub, 0), Vector2(size.x, h * 0.5),
		Vector2(size.x - nub, h), Vector2(nub, h), Vector2(0, h * 0.5),
	])
	draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, border, 1.0, true)
	# 两侧的连接口
	draw_rect(Rect2(0, h * 0.5 - NOTCH_H * 0.5, 3, NOTCH_H), border, true)
	draw_rect(Rect2(size.x - 3, h * 0.5 - NOTCH_H * 0.5, 3, NOTCH_H), border, true)


func draw_socket(r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.22)
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	draw_style_box(sb, r)


# ============================================================ 连接点

# 返回本积木的所有连接点（局部坐标），canvas 拿去做吸附
func connections() -> Array:
	var out := []
	var sh := shape()
	if sh == "stack" or sh == "hat":
		out.append({ "kind": "prev", "block": self, "slot": "", "pos": Vector2(NOTCH_X, 0.0) })
	if sh == "stack":
		out.append({ "kind": "next", "block": self, "slot": "", "pos": Vector2(NOTCH_X, size.y) })
	if sh == "reporter" or sh == "boolean":
		out.append({ "kind": "output", "block": self, "slot": "", "pos": Vector2(0.0, size.y * 0.5) })
	for name in _stmt_rects:
		var r: Rect2 = _stmt_rects[name]
		out.append({ "kind": "stmt", "block": self, "slot": name,
			"pos": Vector2(r.position.x, r.position.y + STMT_MIN_H * 0.5) })
	for name in _value_pos:
		if inputs.has(name):
			continue   # 已经塞了东西，这个槽不再是空位
		out.append({ "kind": "value", "block": self, "slot": name, "pos": _value_pos[name] })
	return out


func set_selected(v: bool) -> void:
	_selected = v
	queue_redraw()


# 取字段值（导出脚本时用）
func field_value(name: String) -> Variant:
	if fields.has(name):
		return fields[name]
	return null
