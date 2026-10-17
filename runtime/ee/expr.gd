# 逃生舱①：受限表达式的词法/语法/求值。
#
# 为什么不是"直接塞一段 GDScript"：
#   * 表达式会出现在积木的值槽里，必须能静态查错、能参与优化；
#   * 小孩写的式子不该有能力调 queue_free()；
#   * 它是**受限**语言，我们能保证语义稳定，不会随 Godot 版本变。
#
# 语法（优先级从低到高）：
#   or  →  and  →  not  →  比较  →  ± →  ×÷% →  负号 →  ^ →  基本项
# 基本项：数字、字符串、true/false/null、变量名、函数调用、括号
#
# 用法：
#   var r := Expr.compile("hp * 2 + bonus")
#   if not r.ok: push_error(r.error)
#   var v := Expr.evaluate(r.ast, func(n): return lookup(n))
#
# compile 只做一次，evaluate 可以反复调用——循环里的表达式不会被重复解析。
extends RefCounted

const Values = preload("res://ee/values.gd")

# ---- 编译结果 ---------------------------------------------------------
# { ok: bool, ast: Variant, error: String, pos: int }

static func compile(source: String) -> Dictionary:
	var lx := _Lexer.new(source)
	var tokens := lx.tokenize()
	if lx.error != "":
		return { "ok": false, "ast": null, "error": lx.error, "pos": lx.error_pos }

	var ps := _Parser.new(tokens, source)
	var ast: Variant = ps.parse_program()
	if ps.error != "":
		return { "ok": false, "ast": null, "error": ps.error, "pos": ps.error_pos }

	return { "ok": true, "ast": ast, "error": "", "pos": 0 }


static func evaluate(ast: Variant, lookup: Callable) -> Variant:
	return _eval(ast, lookup)


static func _eval(n: Variant, lookup: Callable) -> Variant:
	if n == null:
		return null
	match n.get("t", ""):
		"num":
			return n["v"]
		"str":
			return n["v"]
		"bool":
			return n["v"]
		"null":
			return null
		"var":
			var name: String = n["name"]
			if lookup.is_valid():
				return lookup.call(name)
			return null
		"neg":
			return -Values.to_number(_eval(n["a"], lookup))
		"not":
			return not Values.to_bool(_eval(n["a"], lookup))
		"bin":
			return _eval_bin(str(n["op"]), n["a"], n["b"], lookup)
		"call":
			return _eval_call(str(n["name"]), n["args"], lookup)
	return null


static func _eval_bin(op: String, a_node: Variant, b_node: Variant, lookup: Callable) -> Variant:
	# 短路：and / or 不先算右边，避免无谓的求值
	match op:
		"and":
			var la: bool = Values.to_bool(_eval(a_node, lookup))
			if not la:
				return false
			return Values.to_bool(_eval(b_node, lookup))
		"or":
			var ra: bool = Values.to_bool(_eval(a_node, lookup))
			if ra:
				return true
			return Values.to_bool(_eval(b_node, lookup))

	var a: Variant = _eval(a_node, lookup)
	var b: Variant = _eval(b_node, lookup)

	match op:
		"+": return Values.add(a, b)
		"-": return Values.sub(a, b)
		"*": return Values.mul(a, b)
		"/": return Values.div(a, b)
		"%": return Values.mod(a, b)
		"^": return pow(Values.to_number(a), Values.to_number(b))
		"==": return Values.equals(a, b)
		"!=": return not Values.equals(a, b)
		"<": return Values.compare(a, b) < 0
		"<=": return Values.compare(a, b) <= 0
		">": return Values.compare(a, b) > 0
		">=": return Values.compare(a, b) >= 0
	return null


static func _eval_call(name: String, arg_nodes: Array, lookup: Callable) -> Variant:
	var args: Array = []
	for a in arg_nodes:
		args.append(_eval(a, lookup))
	var n := args.size()
	var f := func(i: int, d: float) -> float:
		return Values.to_number(args[i]) if i < n else d

	match name:
		"min":
			if n == 0:
				return 0.0
			return minf(f.call(0, 0.0), f.call(1, f.call(0, 0.0)))
		"max":
			if n == 0:
				return 0.0
			return maxf(f.call(0, 0.0), f.call(1, f.call(0, 0.0)))
		"abs": return absf(f.call(0, 0.0))
		"floor": return floor(f.call(0, 0.0))
		"ceil": return ceil(f.call(0, 0.0))
		"round": return Values.round_to_nearest(f.call(0, 0.0))
		"sqrt": return sqrt(f.call(0, 0.0))
		"pow": return pow(f.call(0, 0.0), f.call(1, 1.0))
		"sign": return signf(f.call(0, 0.0))
		"sin": return sin(f.call(0, 0.0))
		"cos": return cos(f.call(0, 0.0))
		"tan": return tan(f.call(0, 0.0))
		"atan2": return atan2(f.call(0, 0.0), f.call(1, 0.0))
		"log": return log(f.call(0, 1.0))
		"exp": return exp(f.call(0, 0.0))
		"clamp": return clampf(f.call(0, 0.0), f.call(1, 0.0), f.call(2, 1.0))
		"lerp": return lerpf(f.call(0, 0.0), f.call(1, 0.0), f.call(2, 0.0))
		"deg2rad": return deg_to_rad(f.call(0, 0.0))
		"rad2deg": return rad_to_deg(f.call(0, 0.0))
		"random":
			return randf_range(f.call(0, 0.0), f.call(1, 1.0))
		"randi":
			var lo := int(f.call(0, 0.0))
			var hi := int(f.call(1, 0.0))
			if hi < lo:
				var t := lo
				lo = hi
				hi = t
			return randi_range(lo, hi)
		"len":
			if n == 0:
				return 0
			var v: Variant = args[0]
			match typeof(v):
				TYPE_STRING, TYPE_STRING_NAME:
					return str(v).length()
				TYPE_ARRAY:
					return (v as Array).size()
				TYPE_DICTIONARY:
					return (v as Dictionary).size()
			return 0
		"str": return Values.to_string_value(args[0] if n > 0 else null)
		"num": return Values.to_number(args[0] if n > 0 else null)
		"bool": return Values.to_bool(args[0] if n > 0 else null)
	return null


# 供编辑器做自动补全与文档
static func function_names() -> PackedStringArray:
	return PackedStringArray([
		"min", "max", "abs", "floor", "ceil", "round", "sqrt", "pow", "sign",
		"sin", "cos", "tan", "atan2", "log", "exp", "clamp", "lerp",
		"deg2rad", "rad2deg", "random", "randi", "len", "str", "num", "bool",
	])


# ============================================================ 词法
class _Lexer:
	var src: String
	var i := 0
	var error := ""
	var error_pos := 0

	func _init(p_src: String) -> void:
		src = p_src

	func tokenize() -> Array:
		var out: Array = []
		while i < src.length():
			var c := src[i]
			if c == " " or c == "\t" or c == "\n" or c == "\r":
				i += 1
				continue
			if _is_digit(c) or (c == "." and i + 1 < src.length() and _is_digit(src[i + 1])):
				out.append(_number())
				continue
			if c == '"' or c == "'":
				var s := _string(c)
				if error != "":
					return out
				out.append(s)
				continue
			if _is_ident_start(c):
				out.append(_ident())
				continue
			var two := src.substr(i, 2)
			if two in ["==", "!=", "<=", ">=", "&&", "||"]:
				out.append({ "k": "op", "v": two, "p": i })
				i += 2
				continue
			if c in ["+", "-", "*", "/", "%", "^", "<", ">", "!", "(", ")", ","]:
				out.append({ "k": "op", "v": c, "p": i })
				i += 1
				continue
			_fail("不认识的字符 '%s'" % c, i)
			return out
		out.append({ "k": "eof", "v": "", "p": src.length() })
		return out

	func _fail(msg: String, pos: int) -> void:
		if error == "":
			error = msg
			error_pos = pos

	func _is_digit(c: String) -> bool:
		return c >= "0" and c <= "9"

	func _is_ident_start(c: String) -> bool:
		return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c.unicode_at(0) > 127

	func _is_ident_char(c: String) -> bool:
		return _is_ident_start(c) or _is_digit(c)

	func _number() -> Dictionary:
		var start := i
		while i < src.length() and (_is_digit(src[i]) or src[i] == "."):
			i += 1
		# 科学计数法
		if i < src.length() and (src[i] == "e" or src[i] == "E"):
			i += 1
			if i < src.length() and (src[i] == "+" or src[i] == "-"):
				i += 1
			while i < src.length() and _is_digit(src[i]):
				i += 1
		var text := src.substr(start, i - start)
		if not text.is_valid_float():
			_fail("数字格式不对：'%s'" % text, start)
			return { "k": "num", "v": 0.0, "p": start }
		return { "k": "num", "v": text.to_float(), "p": start }

	func _string(q: String) -> Dictionary:
		var start := i
		i += 1
		var buf := ""
		while i < src.length():
			var c := src[i]
			if c == "\\" and i + 1 < src.length():
				var n := src[i + 1]
				match n:
					"n": buf += "\n"
					"t": buf += "\t"
					"\\": buf += "\\"
					'"': buf += '"'
					"'": buf += "'"
					_: buf += n
				i += 2
				continue
			if c == q:
				i += 1
				return { "k": "str", "v": buf, "p": start }
			buf += c
			i += 1
		_fail("字符串没有收尾的引号", start)
		return { "k": "str", "v": buf, "p": start }

	func _ident() -> Dictionary:
		var start := i
		while i < src.length() and _is_ident_char(src[i]):
			i += 1
		var name := src.substr(start, i - start)
		match name:
			"true": return { "k": "bool", "v": true, "p": start }
			"false": return { "k": "bool", "v": false, "p": start }
			"null": return { "k": "null", "v": null, "p": start }
			"and": return { "k": "op", "v": "and", "p": start }
			"or": return { "k": "op", "v": "or", "p": start }
			"not": return { "k": "op", "v": "not", "p": start }
		return { "k": "ident", "v": name, "p": start }


# ============================================================ 语法
class _Parser:
	var toks: Array
	var src: String
	var i := 0
	var error := ""
	var error_pos := 0

	func _init(p_toks: Array, p_src: String) -> void:
		toks = p_toks
		src = p_src

	func _peek() -> Dictionary:
		return toks[i]

	func _at_op(v: String) -> bool:
		var t: Dictionary = toks[i]
		return t["k"] == "op" and t["v"] == v

	func _eat_op(v: String) -> bool:
		if _at_op(v):
			i += 1
			return true
		return false

	func _fail(msg: String) -> void:
		if error == "":
			error = msg
			error_pos = toks[i]["p"] if i < toks.size() else src.length()

	func parse_program() -> Variant:
		var e: Variant = _or_expr()
		if error != "":
			return null
		if toks[i]["k"] != "eof":
			_fail("表达式后面还有多余内容")
			return null
		return e

	func _or_expr() -> Variant:
		var a: Variant = _and_expr()
		while error == "" and (_at_op("or") or _at_op("||")):
			i += 1
			var b: Variant = _and_expr()
			a = { "t": "bin", "op": "or", "a": a, "b": b }
		return a

	func _and_expr() -> Variant:
		var a: Variant = _not_expr()
		while error == "" and (_at_op("and") or _at_op("&&")):
			i += 1
			var b: Variant = _not_expr()
			a = { "t": "bin", "op": "and", "a": a, "b": b }
		return a

	func _not_expr() -> Variant:
		if _at_op("not") or _at_op("!"):
			i += 1
			var a: Variant = _not_expr()
			return { "t": "not", "a": a }
		return _comparison()

	func _comparison() -> Variant:
		var a: Variant = _additive()
		for op in ["==", "!=", "<=", ">=", "<", ">"]:
			if _at_op(op):
				i += 1
				var b: Variant = _additive()
				return { "t": "bin", "op": op, "a": a, "b": b }
		return a

	func _additive() -> Variant:
		var a: Variant = _multiplicative()
		while error == "" and (_at_op("+") or _at_op("-")):
			var op := str(toks[i]["v"])
			i += 1
			var b: Variant = _multiplicative()
			a = { "t": "bin", "op": op, "a": a, "b": b }
		return a

	func _multiplicative() -> Variant:
		var a: Variant = _unary()
		while error == "" and (_at_op("*") or _at_op("/") or _at_op("%")):
			var op := str(toks[i]["v"])
			i += 1
			var b: Variant = _unary()
			a = { "t": "bin", "op": op, "a": a, "b": b }
		return a

	func _unary() -> Variant:
		if _at_op("-"):
			i += 1
			return { "t": "neg", "a": _unary() }
		if _at_op("+"):
			i += 1
			return _unary()
		return _power()

	func _power() -> Variant:
		var a: Variant = _primary()
		if error == "" and _at_op("^"):
			i += 1
			# 右结合：2^3^2 = 2^(3^2)
			var b: Variant = _unary()
			return { "t": "bin", "op": "^", "a": a, "b": b }
		return a

	func _primary() -> Variant:
		var t: Dictionary = _peek()
		if t["k"] == "num" or t["k"] == "str" or t["k"] == "bool":
			i += 1
			return { "t": t["k"], "v": t["v"] }
		if t["k"] == "null":
			i += 1
			return { "t": "null" }
		if t["k"] == "ident":
			i += 1
			var name := str(t["v"])
			if _at_op("("):
				i += 1
				var args: Array = []
				if not _at_op(")"):
					while true:
						args.append(_or_expr())
						if error != "":
							return null
						if _eat_op(","):
							continue
						break
				if not _eat_op(")"):
					_fail("函数调用的括号没有闭合")
					return null
				return { "t": "call", "name": name, "args": args }
			return { "t": "var", "name": name }
		if _eat_op("("):
			var e: Variant = _or_expr()
			if not _eat_op(")"):
				_fail("括号没有闭合")
				return null
			return e
		_fail("这里不该出现 '%s'" % str(t["v"]))
		return null
