extends Node

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var hero := get_parent().get_node_or_null("Hero")
	print("RESULT 是刚体=", (hero is RigidBody3D) if hero else false)
	if hero is RigidBody3D:
		print("RESULT 冻结=", hero.freeze)
	var mesh = hero.get_node_or_null("EE_Mesh") if hero else null
	if mesh and mesh.mesh:
		var mat = mesh.get_surface_override_material(0)
		var tex = mat.get_texture(BaseMaterial3D.TEXTURE_ALBEDO) if mat else null
		print("RESULT 有贴图=", tex != null)
	var light = get_parent().get_node_or_null("EE_Light")
	print("RESULT 有灯=", light != null)
	if light:
		print("RESULT 灯颜色=", light.light_color, " 亮度=", light.light_energy)
	var r = hero.get_node_or_null("Runner") if hero else null
	if r:
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()