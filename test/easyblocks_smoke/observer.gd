extends Node

var f := 0

func _process(_delta: float) -> void:
	f += 1
	if f != 40:
		return
	var c := get_parent().get_node_or_null("Character") as Node2D
	var r := get_parent().get_node_or_null("Character/Runner")
	print("RESULT pos=", c.position if c else "NO_CHARACTER")
	if r:
		print("RESULT threads=", r.get_thread_count(), " errors=", r.get_errors(), " warnings=", r.get_warnings())
	get_tree().quit()
