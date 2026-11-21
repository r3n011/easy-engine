extends Node

func _ready() -> void:
	# 等 3 秒真实时间（无渲染时 _process 帧率不可靠，物理是按固定步长走的）
	await get_tree().create_timer(3.0).timeout
	var main := get_parent()
	var hero := main.get_node_or_null("Hero")
	print("RESULT 落地 y=", snappedf(hero.position.y, 0.01) if hero else "?")
	print("RESULT 是刚体=", (hero is RigidBody3D) if hero else false)
	if hero is RigidBody3D:
		print("RESULT 质量=", hero.mass, " 速度=", hero.linear_velocity.round())
	var r := hero.get_node_or_null("Runner") if hero else null
	if r:
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()