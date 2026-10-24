extends Node

var f := 0

func _process(_delta: float) -> void:
	f += 1
	if f != 30:
		return
	var r := get_parent().get_node_or_null("Runner")
	if r == null:
		print("RESULT 没有 Runner")
	else:
		print("RESULT 角色 y=", get_parent().position.y)
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()