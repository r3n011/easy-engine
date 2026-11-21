extends Node

func _ready() -> void:
	await get_tree().create_timer(0.4).timeout
	var hero := get_parent().get_node_or_null("Hero")
	print("RESULT 颜色=", hero.modulate, " z=", hero.z_index)
	print("RESULT 有特效=", hero.modulate != Color(1,1,1,1))
	print("RESULT 最前=", hero.z_index == 1000)
	var r := hero.get_node_or_null("Runner")
	if r:
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()