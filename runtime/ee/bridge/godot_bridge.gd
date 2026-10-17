# Godot 节点桥：把 op 的效果落到真实 Godot 节点上。
#
# 这是 M3 的核心：**调度器、op 实现、值语义一行都没有改**，只换掉了这一层。
# M2 用无渲染实现把语义测出来，M3 换成真节点，这就是"桥"这层隔离的价值。
#
# 坐标约定（只在这一层转换，别的层一律用 Scratch 坐标）：
#   位置     Scratch (x, y) 中心为原点、y 向上  →  Godot Vector2(x, -y)（舞台根在视口中心）
#   方向     Scratch 0=上 90=右（逆时针）        →  rotation = deg_to_rad(direction - 90)
#   大小     百分比                              →  node.scale = percent / 100
extends "res://ee/bridge/node_bridge.gd"

const TEMPLATES_PATH := "res://ee/defs/templates.json"
const EFFECTS_SHADER := "res://ee/shaders/sprite_effects.gdshader"

# 角色挂到哪；由 player 场景设置
var stage_root: Node2D = null
# 变量监视器挂到哪
var monitor_root: Node = null
# .ee 所在目录，用于解析相对资源路径（如 "assets/apple.png"）
var asset_base := "res://"

var _templates := {}
var _effect_shader: Shader = null
var _texture_cache := {}
var _monitors := {}          # name -> Label
var _code_cache := {}        # 源码 -> GDScript（循环里每帧执行，必须缓存）


func _init() -> void:
	if ResourceLoader.exists(TEMPLATES_PATH):
		var f := FileAccess.open(TEMPLATES_PATH, FileAccess.READ)
		var d: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(d) == TYPE_DICTIONARY:
			for t in d.get("templates", []):
				_templates[str(t.get("id", ""))] = t
	if ResourceLoader.exists(EFFECTS_SHADER):
		_effect_shader = load(EFFECTS_SHADER)


func stage_size() -> Vector2:
	return get_stage_size()


# ---------------------------------------------------------------- 资源

func _resolve_asset(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	return asset_base.path_join(path)


func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var full := _resolve_asset(path)
	var tex: Texture2D = null

	# 优先走资源加载（编辑器导入过的资源）
	if ResourceLoader.exists(full):
		var res: Resource = load(full)
		if res is Texture2D:
			tex = res

	# 回退：直接把文件当图片读。
	# 为什么需要这条：项目的图片素材不在 Godot 的导入流程里（它们属于 .ee 项目，
	# 不属于引擎工程），没有 .import 文件时 load() 拿不到贴图。
	if tex == null:
		var img := Image.new()
		if img.load(full) == OK:
			tex = ImageTexture.create_from_image(img)

	if tex == null:
		warnings.append("找不到图片素材：" + full)
	_texture_cache[path] = tex
	return tex


# ---------------------------------------------------------------- 建节点

func create_visual(target) -> void:
	if stage_root == null or target == null:
		return
	var tmpl: Dictionary = _templates.get(str(target.template), {})
	if tmpl.is_empty():
		tmpl = { "root": "Node2D", "children": [{ "name": "Costume", "type": "Sprite2D", "role": "costume" }] }

	var root: Node = ClassDB.instantiate(str(tmpl.get("root", "Node2D")))
	root.name = "T_" + str(target.id).replace("#", "_")
	if tmpl.has("defaults"):
		for k in tmpl["defaults"]:
			if root.has_method("set_" + str(k)):
				root.call("set_" + str(k), tmpl["defaults"][k])

	for c in tmpl.get("children", []):
		var child: Node = ClassDB.instantiate(str(c.get("type", "Node2D")))
		child.name = str(c.get("name", "Child"))
		if str(c.get("role", "")) == "costume" and _effect_shader != null:
			var mat := ShaderMaterial.new()
			mat.shader = _effect_shader
			(child as CanvasItem).material = mat
		root.add_child(child)

	stage_root.add_child(root)
	target.node = root

	# 把 Target 里的初始状态铺到节点上
	set_position(target, target.state.get("position", Vector2.ZERO))
	set_direction(target, float(target.state.get("direction", 90.0)))
	set_scale_percent(target, float(target.state.get("scale_percent", 100.0)))
	set_visible(target, bool(target.state.get("visible", true)))
	if not target.costumes.is_empty():
		set_costume(target, str(target.state.get("costume", target.costumes[0].get("name", ""))))
	_log("create_visual", target, [str(target.template)])


func destroy_visual(target) -> void:
	if target != null and target.node != null:
		target.node.queue_free()
		target.node = null
	_log("destroy_visual", target, [])


func _costume_node(target) -> CanvasItem:
	if target == null or target.node == null:
		return null
	for c in target.node.get_children():
		if c is Sprite2D or c is TextureRect or c is AnimatedSprite2D:
			return c
	return null


# ---------------------------------------------------------------- 变换

func get_position(target) -> Vector2:
	var node: Node2D = target.node if target != null else null
	if node == null:
		return super.get_position(target)
	var p := node.position
	return Vector2(p.x, -p.y)


func set_position(target, pos: Vector2) -> void:
	super.set_position(target, pos)
	var node: Node2D = target.node if target != null else null
	if node != null:
		node.position = Vector2(pos.x, -pos.y)


func get_direction(target) -> float:
	var node: Node2D = target.node if target != null else null
	if node == null:
		return super.get_direction(target)
	return rad_to_deg(node.rotation) + 90.0


func set_direction(target, degrees: float) -> void:
	super.set_direction(target, degrees)
	var node: Node2D = target.node if target != null else null
	if node != null:
		node.rotation = deg_to_rad(degrees - 90.0)


func get_rotation(target) -> float:
	return deg_to_rad(get_direction(target))


func set_rotation(target, radians_: float) -> void:
	set_direction(target, rad_to_deg(radians_) + 90.0)


func get_scale_percent(target) -> float:
	var node: Node2D = target.node if target != null else null
	if node == null:
		return super.get_scale_percent(target)
	return node.scale.x * 100.0


func set_scale_percent(target, percent: float) -> void:
	super.set_scale_percent(target, percent)
	var node: Node2D = target.node if target != null else null
	if node != null:
		var s := percent / 100.0
		node.scale = Vector2(s, s)


# 角色的包围盒（用造型贴图尺寸 × 缩放），碰边与碰撞判定都用它
func get_size(target) -> Vector2:
	var ci := _costume_node(target)
	var base := Vector2(32, 32)
	if ci is Sprite2D and (ci as Sprite2D).texture != null:
		base = (ci as Sprite2D).texture.get_size()
	elif ci is TextureRect and (ci as TextureRect).texture != null:
		base = (ci as TextureRect).texture.get_size()
	var pct := get_scale_percent(target) / 100.0
	return base * pct


# ---------------------------------------------------------------- 外观

func set_visible(target, v: bool) -> void:
	super.set_visible(target, v)
	var node: CanvasItem = target.node if target != null else null
	if node != null:
		node.visible = v


func set_costume(target, name: String) -> void:
	super.set_costume(target, name)
	var ci := _costume_node(target)
	if ci == null:
		return
	for c in target.costumes:
		if str(c.get("name", "")) == name:
			var tex := _texture(str(c.get("asset", "")))
			if tex != null:
				if ci is Sprite2D:
					(ci as Sprite2D).texture = tex
				elif ci is TextureRect:
					(ci as TextureRect).texture = tex
			return


func _material_of(target) -> ShaderMaterial:
	var ci := _costume_node(target)
	if ci == null:
		return null
	var m := ci.material
	if m is ShaderMaterial:
		return m
	return null


func set_effect(target, effect: String, value: float) -> void:
	super.set_effect(target, effect, value)
	var mat := _material_of(target)
	if mat == null:
		return
	var uniform := _effect_uniform(effect)
	if uniform != "":
		mat.set_shader_parameter(uniform, value)


func clear_effects(target) -> void:
	super.clear_effects(target)
	var mat := _material_of(target)
	if mat == null:
		return
	for u in ["ghost", "brightness", "hue_shift", "fisheye", "whirl", "pixelate", "mosaic"]:
		mat.set_shader_parameter(u, 0.0)


func _effect_uniform(effect: String) -> String:
	match effect:
		"color": return "hue_shift"
		"ghost": return "ghost"
		"brightness": return "brightness"
		"fisheye": return "fisheye"
		"whirl": return "whirl"
		"pixelate": return "pixelate"
		"mosaic": return "mosaic"
	return ""


func set_layer(target, mode: String, layers: int) -> void:
	super.set_layer(target, mode, layers)
	if target == null or target.node == null or stage_root == null:
		return
	var n: Node = target.node
	var idx: int = n.get_index()
	var total: int = stage_root.get_child_count()
	match mode:
		"front": idx = total - 1
		"back": idx = 0
		"forward": idx = mini(idx + maxi(1, layers), total - 1)
		"backward": idx = maxi(idx - maxi(1, layers), 0)
	stage_root.move_child(n, idx)


# ---------------------------------------------------------------- 说话

func show_say(target, text: String, _mode: String, _seconds: float) -> void:
	super.show_say(target, text, _mode, _seconds)
	if target == null or target.node == null:
		return
	var node: Node = target.node
	var bubble: Label = node.get_node_or_null("SayBubble")
	if text.is_empty():
		if bubble != null:
			bubble.queue_free()
		return
	if bubble == null:
		bubble = Label.new()
		bubble.name = "SayBubble"
		bubble.add_theme_color_override("font_color", Color.WHITE)
		bubble.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		bubble.add_theme_constant_override("outline_size", 6)
		bubble.position = Vector2(-40, -56)
		node.add_child(bubble)
	bubble.text = text


# ---------------------------------------------------------------- 侦测

# 把角色当作以 position 为中心、size 为边长的矩形做 AABB 判定。
# （有意不做像素级判定：见方案 D4 —— 观感更好、性能更高）
func _rect_of(target) -> Rect2:
	var p: Vector2 = get_position(target)
	var s: Vector2 = get_size(target)
	return Rect2(p - s * 0.5, s)


func is_touching(target, other: Variant) -> bool:
	var mine := _rect_of(target)
	var key := str(other)
	if key == "@mouse":
		var m := get_mouse_position()
		return mine.has_point(m)
	if key == "@edge":
		var half: Vector2 = get_stage_size() * 0.5
		var p: Vector2 = get_position(target)
		var s: Vector2 = get_size(target)
		return p.x - s.x * 0.5 <= -half.x or p.x + s.x * 0.5 >= half.x \
			or p.y - s.y * 0.5 <= -half.y or p.y + s.y * 0.5 >= half.y
	var ref = runtime.resolve_reference(key, null) if runtime != null else null
	if ref == null:
		return false
	if key == "@any_sprite":
		for t in runtime.targets:
			if t != target and _rect_of(t).intersects(mine):
				return true
		return false
	return _rect_of(ref).intersects(mine)


func is_key_pressed(key: String) -> bool:
	match key:
		"space": return Input.is_key_pressed(KEY_SPACE)
		"up": return Input.is_key_pressed(KEY_UP)
		"down": return Input.is_key_pressed(KEY_DOWN)
		"left": return Input.is_key_pressed(KEY_LEFT)
		"right": return Input.is_key_pressed(KEY_RIGHT)
		"any":
			for k in [KEY_SPACE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
					KEY_ENTER, KEY_ESCAPE, KEY_A, KEY_D, KEY_W, KEY_S]:
				if Input.is_key_pressed(k):
					return true
			return false
	if key.length() == 1:
		return Input.is_key_pressed(OS.find_keycode_from_string(key.to_upper()))
	return false


func get_mouse_position() -> Vector2:
	if stage_root == null:
		return Vector2.ZERO
	var p := stage_root.get_local_mouse_position()
	return Vector2(p.x, -p.y)


func is_mouse_pressed() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


# ---------------------------------------------------------------- 声音

func play_sound(target, name: String, wait: bool) -> void:
	super.play_sound(target, name, wait)
	if stage_root == null:
		return
	for s in target.sounds:
		if str(s.get("name", "")) != name:
			continue
		var full := _resolve_asset(str(s.get("asset", "")))
		if not ResourceLoader.exists(full):
			warnings.append("找不到声音素材：" + full)
			return
		var stream := load(full)
		if stream is AudioStream == false:
			return
		var p := AudioStreamPlayer.new()
		p.stream = stream
		stage_root.add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
		return


# ---------------------------------------------------------------- 元积木

func set_property(target, property: String, value: Variant) -> void:
	super.set_property(target, property, value)
	var node: Object = target.node if target != null else null
	if node != null:
		node.set_indexed(NodePath(property), value)


func get_property(target, property: String) -> Variant:
	super.get_property(target, property)
	var node: Object = target.node if target != null else null
	if node == null:
		return null
	return node.get_indexed(NodePath(property))


func call_method(target, method: String, args: Array) -> Variant:
	super.call_method(target, method, args)
	var node: Object = target.node if target != null else null
	if node == null:
		return null
	if not node.has_method(method):
		warnings.append("节点 %s 没有方法 %s" % [target.id, method])
		return null
	return Callable(node, method).callv(args)


func emit_signal_to(target, signal_name: String, args: Array) -> void:
	super.emit_signal_to(target, signal_name, args)
	var node: Object = target.node if target != null else null
	if node == null:
		return
	if not node.has_signal(signal_name):
		warnings.append("节点 %s 没有信号 %s" % [target.id, signal_name])
		return
	Callable(node, "emit_signal").callv([signal_name] + args)


func instantiate(parent, source: String) -> Variant:
	super.instantiate(parent, source)
	var full: String = _resolve_asset(source)
	if not ResourceLoader.exists(full):
		warnings.append("找不到场景：" + full)
		return null
	var packed := load(full)
	if packed is PackedScene == false:
		warnings.append("不是场景文件：" + full)
		return null
	var inst: Node = (packed as PackedScene).instantiate()
	var host: Node = parent.node if parent != null and parent.node != null else stage_root
	if host == null:
		return null
	host.add_child(inst)
	return inst


# ---------------------------------------------------------------- 变量监视器

func set_monitor_visible(name: String, is_list: bool, show: bool) -> void:
	super.set_monitor_visible(name, is_list, show)
	if monitor_root == null:
		return
	if not show:
		if _monitors.has(name):
			(_monitors[name] as Label).queue_free()
			_monitors.erase(name)
		return
	if _monitors.has(name):
		return
	var box := HBoxContainer.new()
	box.name = "M_" + name
	var tag := Label.new()
	tag.text = name + ("" if is_list else "")
	tag.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	box.add_child(tag)
	var val := Label.new()
	val.name = "Value"
	val.add_theme_color_override("font_color", Color.WHITE)
	val.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	val.add_theme_constant_override("outline_size", 5)
	box.add_child(val)
	# 用名字占位，真正的数值由 player 每帧刷新
	_monitors[name] = val
	monitor_root.add_child(box)


func refresh_monitors() -> void:
	if runtime == null:
		return
	for name in _monitors:
		var label: Label = _monitors[name]
		if not is_instance_valid(label):
			continue
		var v: Variant = runtime.get_var(name, "auto", null)
		if typeof(v) == TYPE_ARRAY:
			label.text = JSON.stringify(v)
		else:
			label.text = Values.to_string_value(v)


# ---------------------------------------------------------------- 执行代码（逃生舱②）

# 真正执行用户写的 GDScript。
#
# 做法：扫描用户代码里出现的变量名，把它们**生成为局部变量**，
# 跑完再写回运行时。于是用户可以直接写 `分数 = 分数 + 1`，
# 而不必写 `env.set_var("分数", env.get_var("分数") + 1)`。
func _execute_code(target, source: String) -> void:
	if source.strip_edges().is_empty():
		return
	if runtime == null:
		return

	var names := _candidate_names(target)
	var used: Array = []
	for n in names:
		if _mentions(source, n):
			used.append(n)

	var code := "extends RefCounted\n\nfunc run(env: Object) -> void:\n"
	if target != null and target.node != null:
		code += "\tvar node: Node = env.node()\n"
	for n in used:
		code += "\tvar %s = env.get_var(\"%s\")\n" % [n, n]
	code += "\t\n"
	for line in source.split("\n"):
		code += ("\t" + line + "\n") if not line.strip_edges().is_empty() else "\t\n"
	code += "\t\n"
	for n in used:
		code += "\tenv.set_var(\"%s\", %s)\n" % [n, n]

	var script: GDScript = _code_cache.get(source)
	if script == null:
		script = GDScript.new()
		script.source_code = code
		var err := script.reload()
		if err != OK:
			warnings.append("「执行代码」编译失败，已跳过。请检查语法。")
			return
		# 缓存：同一段代码在循环里每帧都会执行，不能每帧重编译
		_code_cache[source] = script

	var inst = script.new()
	if inst == null:
		warnings.append("「执行代码」实例化失败，已跳过。")
		return
	var env := CodeEnv.new()
	env.runtime = runtime
	env.target = target
	inst.call("run", env)


func _candidate_names(target) -> Array:
	var out: Array = []
	for k in runtime.globals:
		out.append(str(k))
	if target != null:
		for k in target.vars:
			if not out.has(str(k)):
				out.append(str(k))
		for k in target.lists:
			if not out.has(str(k)):
				out.append(str(k))
	for k in runtime.global_lists:
		if not out.has(str(k)):
			out.append(str(k))
	return out


# 只做"出现过这个词"的判断，避免把没引用的变量也生成出来
func _mentions(source: String, name: String) -> bool:
	if name.is_empty():
		return false
	var i := source.find(name)
	while i >= 0:
		var before_ok := i == 0 or not _is_word_char(source[i - 1])
		var e := i + name.length()
		var after_ok := e >= source.length() or not _is_word_char(source[e])
		if before_ok and after_ok:
			return true
		i = source.find(name, i + 1)
	return false


func _is_word_char(c: String) -> bool:
	return c.is_valid_identifier() or c.is_valid_int()


const CodeEnv = preload("res://ee/bridge/code_env.gd")
const Values = preload("res://ee/values.gd")
