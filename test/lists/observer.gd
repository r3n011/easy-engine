extends Node

var f := 0

func _process(_delta: float) -> void:
	f += 1
	if f != 30:
		return
	var r := get_parent().get_node_or_null("Runner")
	if r == null:
		print("RESULT 没有 Runner")
		get_tree().quit()
		return
	print("RESULT 列表=", r.get_list_values("清单"))
	print("RESULT 项目数=", r.get_variable("项目数"))
	print("RESULT 位置=", r.get_variable("位置"))
	print("RESULT 存在=", r.get_variable("存在"))
	print("RESULT 第二项=", r.get_variable("第二项"))
	print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()