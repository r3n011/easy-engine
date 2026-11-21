extends Node

func _ready() -> void:
	await get_tree().create_timer(0.2).timeout
	var hero := get_parent().get_node_or_null("Hero")
	var before: float = hero.position.x
	Input.action_press("ui_right")
	await get_tree().create_timer(0.8).timeout
	Input.action_release("ui_right")
	var after: float = hero.position.x
	print("RESULT 按下右键前 x=", snappedf(before, 0.1), " 后 x=", snappedf(after, 0.1))
	print("RESULT 有移动=", after > before + 10)
	var r := hero.get_node_or_null("Runner")
	if r:
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()