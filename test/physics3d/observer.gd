extends Node

func _ready() -> void:
	await get_tree().create_timer(3.0).timeout
	var main := get_parent()
	var hero := main.get_node_or_null("Hero")
	print("RESULT 落地 y=", snappedf(hero.position.y, 0.01) if hero else "?")
	print("RESULT 是刚体=", (hero is RigidBody3D) if hero else false)
	var r := hero.get_node_or_null("Runner") if hero else null
	if r:
		print("RESULT 碰到变量=", r.get_variable("碰到"))
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()