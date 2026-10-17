# 值语义：积木里所有"取值/比较/拼接"的唯一规则来源。
#
# 为什么必须集中在这里：如果让每个 op 自己决定怎么把 "10" 变成数字，
# 迟早会出现「a + b」和「a > b」对同一个值给出不同答案的情况。
#
# 我们的规则（有意做得比 JavaScript 好预测，又比强类型语言宽松）：
#
#   转数字   数字→本身  布尔→0/1  null→0
#            字符串→trim 后能解析就用，否则 0（空串也是 0）
#            数组/字典→0
#   转字符串 数字→整数值不带 .0；非有限值用 Infinity/NaN
#            布尔→"true"/"false"    null→""    数组/字典→JSON
#   转布尔   null→false  数字→非 0  字符串→非空（"false" 也是 true！）
#   比较     两边都能当数字 → 数字比较；否则字符串比较（区分大小写）
#
# 「两边都能当数字」的判定见 is_numeric_like()：数字、布尔、以及能解析成数字的字符串。
# 这条规则让 "10" > "9" 为 false（数字比较），符合直觉。
extends RefCounted

# ---- 判断 -------------------------------------------------------------

static func is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

static func is_string(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME

static func is_bool(v: Variant) -> bool:
	return typeof(v) == TYPE_BOOL

# 能否当作数字使用（用于决定"数字比较"还是"字符串比较"）
static func is_numeric_like(v: Variant) -> bool:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return true
		TYPE_STRING, TYPE_STRING_NAME:
			return _string_is_numeric(str(v))
		TYPE_NIL:
			return true
	return false

static func _string_is_numeric(s: String) -> bool:
	var t := s.strip_edges()
	if t.is_empty():
		return true   # 空串按 0 处理，视为数字
	return t.is_valid_float() or t.is_valid_int()

# ---- 转换 -------------------------------------------------------------

static func to_number(v: Variant) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return float(v)
		TYPE_BOOL:
			return 1.0 if v else 0.0
		TYPE_NIL:
			return 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			var t := str(v).strip_edges()
			if t.is_empty():
				return 0.0
			if t.is_valid_float():
				return t.to_float()
			if t.is_valid_int():
				return float(t.to_int())
			return 0.0
	return 0.0

static func to_int_value(v: Variant) -> int:
	return int(round(to_number(v)))

static func to_string_value(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return ""
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return number_to_string(float(v))
		TYPE_STRING, TYPE_STRING_NAME:
			return str(v)
		TYPE_ARRAY, TYPE_DICTIONARY:
			return JSON.stringify(v)
	return str(v)

# 数值转字符串：整数值不带小数点，非有限值给出可读的名字。
# 这一条要小心，因为 kids 会看到它。
static func number_to_string(n: float) -> String:
	if is_nan(n):
		return "NaN"
	if is_inf(n):
		return "Infinity" if n > 0 else "-Infinity"
	if n == floor(n) and absf(n) < 1e15:
		return str(int(n))
	# 去掉多余的尾零，最多保留 10 位小数
	var s := String.num(n, 10)
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s

static func to_bool(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			# 注意：非空字符串一律为 true，包括字符串 "false"。
			# 这是为了避免「字符串 "false" 到底是真还是假」这种歧义。
			return not str(v).is_empty()
		TYPE_ARRAY:
			return not (v as Array).is_empty()
		TYPE_DICTIONARY:
			return not (v as Dictionary).is_empty()
	return true

# ---- 比较 -------------------------------------------------------------

# 返回 -1 / 0 / 1
static func compare(a: Variant, b: Variant) -> int:
	if is_numeric_like(a) and is_numeric_like(b):
		var x := to_number(a)
		var y := to_number(b)
		if x < y:
			return -1
		if x > y:
			return 1
		return 0
	var sa := to_string_value(a)
	var sb := to_string_value(b)
	if sa < sb:
		return -1
	if sa > sb:
		return 1
	return 0

static func equals(a: Variant, b: Variant) -> bool:
	return compare(a, b) == 0

# ---- 运算（供 core_ops 使用，集中在一处便于日后统一调整）----------------

static func add(a: Variant, b: Variant) -> Variant:
	# 两边都能当数字就做加法；否则按字符串拼接（Scratcher 的直觉）
	if is_numeric_like(a) and is_numeric_like(b):
		return number_result(to_number(a) + to_number(b))
	return to_string_value(a) + to_string_value(b)

static func sub(a: Variant, b: Variant) -> float:
	return to_number(a) - to_number(b)

static func mul(a: Variant, b: Variant) -> float:
	return to_number(a) * to_number(b)

static func div(a: Variant, b: Variant) -> float:
	var d := to_number(b)
	if d == 0.0:
		# 除以零返回 Infinity 而不是 0：静默变成 0 会把 bug 藏起来。
		# 显示层负责把 Infinity 展示成人话。
		var n := to_number(a)
		if n == 0.0:
			return NAN
		return INF if n > 0.0 else -INF
	return to_number(a) / d

static func mod(a: Variant, b: Variant) -> float:
	var x := to_number(a)
	var y := to_number(b)
	if y == 0.0:
		return NAN
	# 取模结果的符号跟随被除数（与 Godot 的 fmod 一致）
	return fmod(x, y)

static func round_to_nearest(a: Variant) -> float:
	var n := to_number(a)
	# 四舍五入，0.5 远离零（10.5 → 11，-10.5 → -11）
	return floor(n + 0.5) if n >= 0.0 else ceil(n - 0.5)

# 整数运算结果仍用 float 承载，但整数值在转字符串时不会带 .0
static func number_result(n: float) -> float:
	return n

# ---- 参数辅助 ---------------------------------------------------------

# 把 op 的某个参数取出来并求值前的原始值（值已在编译期展开为字面量或表达式节点）
static func clampf01(v: float) -> float:
	return clampf(v, 0.0, 1.0)
