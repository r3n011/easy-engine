extends Node

func _ready() -> void:
	await get_tree().create_timer(0.5).timeout
	var hero := get_parent().get_node_or_null("Hero")
	print("RESULT 造型=", hero.animation if hero else "?")
	var p = hero.get_node_or_null("AudioStreamPlayer") if hero else null
	print("RESULT 音量db=", snappedf(p.volume_db, 0.01) if p else "?")
	var r = hero.get_node_or_null("Runner") if hero else null
	if r:
		print("RESULT 警告=", r.get_warnings(), " 错误=", r.get_errors())
	get_tree().quit()