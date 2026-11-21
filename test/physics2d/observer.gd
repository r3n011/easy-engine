extends Node

func _ready() -> void:
	await get_tree().create_timer(3.0).timeout
	var hero := get_parent().get_node_or_null("Hero")
	print("RESULT 落地 y=", snappedf(hero.position.y, 0.1) if hero else "?")
	print("RESULT 是刚体=", (hero is RigidBody2D) if hero else false)
	if hero is RigidBody2D:
		print("RESULT 质量=", hero.mass, " 速度=", hero.linear_velocity.round())
	var r := hero.get_node_or_null("Runner") if hero else null
	if r:
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()