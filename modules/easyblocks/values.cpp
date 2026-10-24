/**************************************************************************/
/*  values.cpp                                                            */
/**************************************************************************/

#include "values.h"

#include "core/io/json.h"
#include "core/math/math_funcs.h"

namespace EBValues {

bool is_number(const Variant &v) {
	return v.get_type() == Variant::INT || v.get_type() == Variant::FLOAT;
}

static bool _string_is_numeric(const String &p_s) {
	String t = p_s.strip_edges();
	if (t.is_empty()) {
		return true; // 空串按 0 处理
	}
	return t.is_valid_float() || t.is_valid_int();
}

bool is_numeric_like(const Variant &v) {
	switch (v.get_type()) {
		case Variant::INT:
		case Variant::FLOAT:
		case Variant::BOOL:
			return true;
		case Variant::STRING:
		case Variant::STRING_NAME:
			return _string_is_numeric(String(v));
		case Variant::NIL:
			return true;
		default:
			return false;
	}
}

double to_number(const Variant &v) {
	switch (v.get_type()) {
		case Variant::INT:
		case Variant::FLOAT:
			return double(v);
		case Variant::BOOL:
			return bool(v) ? 1.0 : 0.0;
		case Variant::STRING:
		case Variant::STRING_NAME: {
			String t = String(v).strip_edges();
			if (t.is_empty()) {
				return 0.0;
			}
			if (t.is_valid_float()) {
				return t.to_float();
			}
			if (t.is_valid_int()) {
				return double(t.to_int());
			}
			return 0.0;
		}
		default:
			return 0.0;
	}
}

int to_int(const Variant &v) {
	return int(Math::round(to_number(v)));
}

String to_string(const Variant &v) {
	switch (v.get_type()) {
		case Variant::NIL:
			return String();
		case Variant::BOOL:
			return bool(v) ? "true" : "false";
		case Variant::INT:
			return itos(int64_t(v));
		case Variant::FLOAT: {
			const double n = double(v);
			if (Math::is_nan(n)) {
				return "NaN";
			}
			if (Math::is_inf(n)) {
				return n > 0 ? "Infinity" : "-Infinity";
			}
			if (n == Math::floor(n) && Math::abs(n) < 1e15) {
				return itos(int64_t(n));
			}
			String s = String::num(n, 10);
			if (s.contains(".")) {
				s = s.rstrip("0").rstrip(".");
			}
			return s;
		}
		case Variant::STRING:
		case Variant::STRING_NAME:
			return String(v);
		case Variant::ARRAY:
		case Variant::DICTIONARY:
			return JSON::stringify(v, "", false, true);
		default:
			return String(v);
	}
}

bool to_bool(const Variant &v) {
	switch (v.get_type()) {
		case Variant::NIL:
			return false;
		case Variant::BOOL:
			return bool(v);
		case Variant::INT:
		case Variant::FLOAT:
			return to_number(v) != 0.0;
		case Variant::STRING:
		case Variant::STRING_NAME:
			// 非空字符串一律为真，包括字符串 "false"
			return !String(v).is_empty();
		case Variant::ARRAY:
			return !Array(v).is_empty();
		case Variant::DICTIONARY:
			return !Dictionary(v).is_empty();
		default:
			return true;
	}
}

int compare(const Variant &a, const Variant &b) {
	if (is_numeric_like(a) && is_numeric_like(b)) {
		const double x = to_number(a);
		const double y = to_number(b);
		if (x < y) {
			return -1;
		}
		if (x > y) {
			return 1;
		}
		return 0;
	}
	const String sa = to_string(a);
	const String sb = to_string(b);
	if (sa < sb) {
		return -1;
	}
	if (sa > sb) {
		return 1;
	}
	return 0;
}

bool equals(const Variant &a, const Variant &b) {
	return compare(a, b) == 0;
}

Variant add(const Variant &a, const Variant &b) {
	if (is_numeric_like(a) && is_numeric_like(b)) {
		return to_number(a) + to_number(b);
	}
	return to_string(a) + to_string(b);
}

} // namespace EBValues
