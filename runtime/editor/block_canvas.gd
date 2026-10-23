# 积木画布：拖拽、吸附、成串。
#
# 所有拖拽逻辑集中在这里，积木自己不吃鼠标事件（只有字段控件吃）。
# 理由：连接关系是全画布范围的（要判断"离哪个连接点最近"），
# 分散到各个积木里会变成一堆互相转发的事件，很难调。
extends Control

const BlockView = preload("res://editor/block_view.gd")

const SNAP_DIST := 34.0

var defs                       # BlockDefs

var roots := []                # 自由（没接在别人身上）的积木根
var dragging = null            # 正在拖的根积木
var drag_offset := Vector2.ZERO
var _snap_candidate = null     # {target_conn, drag_conn, dist}
var _trash_rect := Rect2()     # 右下角垃圾桶在画布里的位置

signal changed                 # 结构或字段变了，通知编辑器

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func setup(p_defs) -> void:
	defs = p_defs


# ============================================================ 增删

func new_block(block_id: String, at: Vector2):
	var b = instantiate(block_id)
	if b == null:
		return null
	add_child(b)
	roots.append(b)
	b.attached_as = "free"
	b.position = at
	b.relayout()
	changed.emit()
	return b


# 只造积木，不挂进画布也不登记（反序列化时用）
func instantiate(block_id: String):
	var d = defs.def(block_id)
	if d.is_empty():
		push_warning("没有这个积木：" + block_id)
		return null
	var b = BlockView.new()
	b.setup(d)
	b.changed.connect(_on_block_changed)
	return b


func add_top(b, at: Vector2) -> void:
	add_child(b)
	roots.append(b)
	b.attached_as = "free"
	b.attached_owner = null
	b.attached_slot = ""
	b.position = at
	b.relayout()


func delete_block(b) -> void:
	if b == null:
		return
	var root: Control = _stack_root_of(b)
	_detach(root)
	roots.erase(root)
	root.queue_free()
	_compact()
	changed.emit()


func clear_all() -> void:
	for b in roots.duplicate():
		delete_block(b)
	roots.clear()
	changed.emit()


func _on_block_changed() -> void:
	_compact()
	changed.emit()


# ============================================================ 选中/命中

func _all_blocks() -> Array:
	var out := []
	for r in roots:
		_collect(r, out)
	return out


func _collect(b, out: Array) -> void:
	out.append(b)
	for name in b.inputs:
		_collect(b.inputs[name], out)
	for name in b.stmt_slots:
		for c in b.stmt_slots[name]:
			_collect(c, out)
	if b.next_block != null:
		_collect(b.next_block, out)


func _local_pos(b) -> Vector2:
	return b.global_position - global_position


func pick(pos: Vector2):
	# 从上往下找，先看子积木（它们是盖在上面的）
	var found = null
	for b in _all_blocks():
		var r := Rect2(_local_pos(b), b.size)
		if r.has_point(pos):
			found = b   # 继续找，越晚遍历到的越深
	return found


# 拖一个积木时，一起动的是它和它下面的整串（next 链是子节点，本来就跟着走）
func _stack_root_of(b):
	while true:
		if b.attached_as == "next":
			b = b.attached_owner
			continue
		break
	return b


func _deepest(b):
	while b.next_block != null:
		b = b.next_block
	return b


# ============================================================ 拖拽

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var b = pick(event.position)
		if b != null:
			_begin_drag(b, event.position)
			grab_focus()
			accept_event()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var b2 = pick(event.position)
		if b2 != null:
			delete_block(b2)
			accept_event()
		return


# 拖动过程中鼠标可能跑到画布外面（比如从调色板里拖出来），
# 所以移动与松开用全局 _input 处理，而不是 _gui_input。
func _input(event: InputEvent) -> void:
	if dragging == null:
		return
	if event is InputEventMouseMotion:
		dragging.position = get_global_mouse_position() - global_position + drag_offset
		_update_snap()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag()


func _begin_drag(b, pos: Vector2) -> void:
	var root: Control = b
	_detach(root)
	roots.erase(root)

	# 换个父节点，但位置别动（视觉上不能跳）
	var gp: Vector2 = root.global_position
	if root.get_parent() != null:
		root.get_parent().remove_child(root)
	add_child(root)
	root.global_position = gp

	dragging = root
	drag_offset = root.position - pos
	root.set_selected(true)
	move_child(root, get_child_count() - 1)


# 从调色板里拖出新积木：建好之后直接进入拖拽状态
func spawn_and_drag(block_id: String, use_offset := Vector2(26, 13)) -> void:
	var mouse := get_global_mouse_position() - global_position
	var b = new_block(block_id, mouse + use_offset)
	if b == null:
		return
	roots.erase(b)
	dragging = b
	drag_offset = use_offset
	b.set_selected(true)
	move_child(b, get_child_count() - 1)
	_update_snap()


func _update_snap() -> void:
	_snap_candidate = null
	if dragging == null:
		return
	var drag_conns := _open_connections(dragging)
	var target_conns := _available_connections(dragging)
	var best := SNAP_DIST
	for dc in drag_conns:
		var dp: Vector2 = dc["pos"]
		for tc in target_conns:
			if not _compatible(dc, tc):
				continue
			var d: float = dp.distance_to(tc["pos"])
			if d < best:
				best = d
				_snap_candidate = { "drag": dc, "target": tc, "dist": d }
	queue_redraw()


# 被拖积木露在外面的连接点
func _open_connections(b) -> Array:
	var out := []
	var base := _local_pos(b)
	for c in b.connections():
		if c["kind"] == "prev" or c["kind"] == "output":
			out.append({ "kind": c["kind"], "block": b, "slot": c["slot"], "pos": base + c["pos"] })
	return out


# 画布上所有可作为落点的连接点（在被拖的子树之外）
func _available_connections(exclude) -> Array:
	var skip := {}
	_mark_subtree(exclude, skip)
	var out := []
	for b in _all_blocks():
		if skip.has(b):
			continue
		var base := _local_pos(b)
		for c in b.connections():
			var k := str(c["kind"])
			if k == "next" or k == "stmt" or k == "value":
				out.append({ "kind": k, "block": b, "slot": c["slot"], "pos": base + c["pos"] })
	return out


func _mark_subtree(b, out: Dictionary) -> void:
	if b == null:
		return
	out[b] = true
	for name in b.inputs:
		_mark_subtree(b.inputs[name], out)
	for name in b.stmt_slots:
		for c in b.stmt_slots[name]:
			_mark_subtree(c, out)
	if b.next_block != null:
		_mark_subtree(b.next_block, out)


func _compatible(drag_conn: Dictionary, target_conn: Dictionary) -> bool:
	var d := str(drag_conn["kind"])
	var t := str(target_conn["kind"])
	if d == "prev":
		return t == "next" or t == "stmt"
	if d == "output":
		return t == "value"
	return false


func _end_drag() -> void:
	var root = dragging
	dragging = null
	root.set_selected(false)

	if _trash_rect.has_point(root.position + Vector2(10, 10)):
		delete_block(root)
		_snap_candidate = null
		queue_redraw()
		return

	if _snap_candidate != null and _snap_candidate["dist"] <= SNAP_DIST:
		var t = _snap_candidate["target"]
		match str(t["kind"]):
			"next":
				_attach_next(t["block"], root)
			"stmt":
				_attach_stmt(t["block"], str(t["slot"]), root)
			"value":
				_attach_value(t["block"], str(t["slot"]), root)

	_snap_candidate = null
	if root.attached_as == "" or root.attached_as == "free":
		root.attached_as = "free"
		if not roots.has(root):
			roots.append(root)
	_compact()
	changed.emit()


# ============================================================ 连接关系

func _detach(b) -> void:
	if b == null:
		return
	match b.attached_as:
		"next":
			if b.attached_owner != null:
				b.attached_owner.next_block = null
		"stmt":
			if b.attached_owner != null:
				var list: Array = b.attached_owner.stmt_slots.get(b.attached_slot, [])
				list.erase(b)
		"value":
			if b.attached_owner != null:
				b.attached_owner.inputs.erase(b.attached_slot)
	b.attached_as = "free"
	b.attached_owner = null
	b.attached_slot = ""


func _attach_next(parent, b) -> void:
	attach_next(parent, b)


func attach_next(parent, b) -> void:
	_detach(b)
	var old_next = parent.next_block
	parent.next_block = b
	if b.get_parent() != null:
		b.get_parent().remove_child(b)
	parent.add_child(b)
	b.attached_as = "next"
	b.attached_owner = parent
	b.attached_slot = ""
	b.position = Vector2(0, parent.body_h)
	# 原来挂在下面的那串接到新积木的末尾
	if old_next != null and old_next != b:
		attach_next(_deepest(b), old_next)


func _attach_stmt(owner, slot: String, b) -> void:
	attach_stmt(owner, slot, b)


# 语句槽里只放"一串"积木：已经有一串就接到它的末尾，
# 而不是并排放两个独立的根 —— 这样才与 .ee 里的链表表示一致。
func attach_stmt(owner, slot: String, b) -> void:
	_detach(b)
	if not owner.stmt_slots.has(slot):
		owner.stmt_slots[slot] = []
	var list: Array = owner.stmt_slots[slot]
	if list.is_empty():
		if b.get_parent() != null:
			b.get_parent().remove_child(b)
		owner.add_child(b)
		list.append(b)
		b.attached_as = "stmt"
		b.attached_owner = owner
		b.attached_slot = slot
	else:
		attach_next(_deepest(list[0]), b)


func _attach_value(owner, slot: String, b) -> void:
	attach_value(owner, slot, b)


func attach_value(owner, slot: String, b) -> void:
	_detach(b)
	if b.get_parent() != null:
		b.get_parent().remove_child(b)
	owner.add_child(b)
	owner.inputs[slot] = b
	b.attached_as = "value"
	b.attached_owner = owner
	b.attached_slot = slot


# ============================================================ 排布与绘制

func _compact() -> void:
	for r in roots:
		if is_instance_valid(r):
			r.relayout()
	for b in _all_blocks():
		if is_instance_valid(b):
			b.relayout()
	queue_redraw()


func relayout_all() -> void:
	_compact()


func _draw() -> void:
	# 网格
	var step := 24.0
	var c := Color(1, 1, 1, 0.035)
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), c, 1.0)
		x += step
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), c, 1.0)
		y += step

	# 吸附提示
	if _snap_candidate != null:
		var tc = _snap_candidate["target"]
		draw_circle(tc["pos"], 7.0, Color(1, 1, 1, 0.45))
		draw_circle(tc["pos"], 3.0, Color(1, 1, 1, 0.9))

	# 垃圾桶
	_trash_rect = Rect2(size.x - 66, size.y - 66, 54, 54)
	var hot := dragging != null and _trash_rect.has_point(dragging.position + Vector2(10, 10))
	draw_rect(_trash_rect, Color(0.75, 0.25, 0.25, 0.85 if hot else 0.35), false, 2.0)
	draw_string(ThemeDB.fallback_font, _trash_rect.position + Vector2(11, 34), "🗑",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9 if hot else 0.5))
