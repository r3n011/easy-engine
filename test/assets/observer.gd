extends Node

var f := 0

func _process(_delta: float) -> void:
	f += 1
	if f != 30:
		return
	var hero := get_parent().get_node_or_null("Hero")
	print("RESULT 当前造型=", hero.animation if hero else "?")
	var r := hero.get_node_or_null("Runner") if hero else null
	if r:
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()