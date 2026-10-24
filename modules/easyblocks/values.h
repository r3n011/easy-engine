/**************************************************************************/
/*  values.h  —— 值语义（转换 / 比较 / 运算）                              */
/**************************************************************************/

#pragma once

#include "core/string/ustring.h"
#include "core/variant/variant.h"

/**
 * 积木里所有String::utf8("取值/比较/拼接")的唯一规则来源。
 * 规则与 C++ 版逐条对应（见 docs/format/EE-SCHEDULER.md §10）：
 *   转数字  数字→本身 布尔→0/1 null→0 字符串→trim 后能解析就用，否则 0
 *   转串    整数值不带 .0；非有限值用 Infinity/NaN
 *   转布尔  null→false 数字→非 0 字符串→非空（"false" 也是 true）
 *   比较    两边都能当数字就数字比较，否则字符串比较
 */
namespace EBValues {

bool is_number(const Variant &v);
bool is_numeric_like(const Variant &v);
double to_number(const Variant &v);
int to_int(const Variant &v);
String to_string(const Variant &v);
bool to_bool(const Variant &v);
int compare(const Variant &a, const Variant &b);
bool equals(const Variant &a, const Variant &b);
Variant add(const Variant &a, const Variant &b);

} // namespace EBValues
