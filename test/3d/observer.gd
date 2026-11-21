extends Node

var f := 0

func _process(_delta: float) -> void:
	f += 1
	if f != 30:
		return
	var main := get_parent()
	var hero := main.get_node_or_null("Hero")
	print("RESULT 角色=", hero)
	if hero:
		print("RESULT 坐标=", hero.position)
		print("RESULT 旋转y=", round(rad_to_deg(hero.rotation.y) * 10) / 10.0)
		print("RESULT 大小=", hero.scale)
		var mesh := hero.get_node_or_null("EE_Mesh")
		print("RESULT 有网格=", mesh != null, " 网格类型=", mesh.get_class() if mesh else "-")
		if mesh and mesh.mesh:
			print("RESULT 网格形状=", mesh.mesh.get_class())
	print("RESULT 有相机=", main.get_node_or_null("EE_Camera") != null)
	var r := hero.get_node_or_null("Runner") if hero else null
	if r:
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()