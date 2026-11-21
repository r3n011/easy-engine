extends Node

var f := 0

func _process(_delta: float) -> void:
	f += 1
	if f != 20:
		return
	var main := get_parent()
	var hero := main.get_node_or_null("Hero")
	var particles := 0
	for c in hero.get_children():
		if c is CPUParticles3D:
			particles += 1
	print("RESULT 坐标=", hero.position)
	print("RESULT 粒子节点数=", particles)
	print("RESULT 有网格=", hero.get_node_or_null("EE_Mesh") != null)
	print("RESULT 有相机=", main.get_node_or_null("EE_Camera") != null)
	var r := hero.get_node_or_null("Runner")
	if r:
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()