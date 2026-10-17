# 「执行代码」积木里 env 对象的实现。
#
# 用户写的 GDScript 拿到的就是它。桥会先扫描代码里出现的变量名，
# 把它们生成成局部变量，跑完再写回运行时——所以用户可以直接写
# `分数 = 分数 + 1`，而不用写冗长的 get_var/set_var。
extends RefCounted

var runtime = null
var target = null


func get_var(name: String) -> Variant:
	return runtime.get_var(name, "auto", target)


func set_var(name: String, value: Variant) -> void:
	runtime.set_var(name, value, "auto", target)


func get_list(name: String) -> Array:
	return runtime.get_list(name, "auto", target)


# 当前角色对应的 Godot 节点（可以直接改属性、调方法）
func node() -> Node:
	return target.node if target != null and target.node != null else null


# 舞台根节点（用来创建东西、找别的角色）
func stage() -> Node:
	return runtime.bridge.stage_root if runtime != null and runtime.bridge != null else null


# 按 id 找另一个角色
func find(id: String) -> Node:
	if runtime == null:
		return null
	var t = runtime.resolve_reference(id, null)
	return t.node if t != null else null
