extends Node

func _ready() -> void:
	await get_tree().create_timer(0.3).timeout
	var hero := get_parent().get_node_or_null("Hero")
	var label = hero.get_node_or_null("EE_Say") if hero else null
	print("RESULT 有气泡=", label != null, " 文字=", label.text if label else "-", " 可见=", label.visible if label else false)
	print("RESULT 大小=", hero.scale if hero else "?")
	await get_tree().create_timer(1.0).timeout
	print("RESULT 1秒后气泡可见=", label.visible if label else false)
	var r := hero.get_node_or_null("Runner") if hero else null
	if r:
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()