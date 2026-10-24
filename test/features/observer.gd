extends Node

var f := 0

func _process(_delta: float) -> void:
	f += 1
	if f != 45:
		return
	var main := get_parent()
	print("RESULT 子节点数=", main.get_child_count())
	for c in main.get_children():
		if c is Node2D:
			print("RESULT ", c.name, " x=", c.position.x, " y=", c.position.y, " 帧=", c.frame if c is Sprite2D else "-")
	var hero := main.get_node_or_null("Hero")
	if hero:
		var r := hero.get_node_or_null("Runner")
		if r:
			print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()