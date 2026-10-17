# 版本与兼容性声明。所有"以后会变"的东西都集中在这里，避免散落各处。
extends RefCounted

# 项目格式版本。改动 .ee 的结构时 +1，并在 migrations/ 里补一个迁移脚本。
const FORMAT_VERSION := 1

# IR 版本。改动 IR 的语义时 +1。IR 缓存以此为失效依据之一。
const IR_VERSION := 1

# 编译器版本。改动编译逻辑时 +1，用于让 .ee 里的 IR 缓存失效。
const COMPILER_VERSION := 1

# 编写本项目时所依据的 Godot API 版本。Godot 升级后，改名/移除的 API
# 通过 API_COMPAT 表做兼容映射（见 api_compat.gd）。
const GODOT_API_VERSION := "4.7.2"

# 扩展定义的 schema 版本。第三方扩展按此版本编写。
const DEFS_SCHEMA_VERSION := 1


# 比较形如 ">=1"、"=2"、"<=3" 的版本约束。
static func satisfies(version: int, constraint: String) -> bool:
	var c := constraint.strip_edges()
	if c.is_empty():
		return true
	if c.begins_with(">="):
		return version >= c.substr(2).to_int()
	if c.begins_with("<="):
		return version <= c.substr(2).to_int()
	if c.begins_with(">"):
		return version > c.substr(1).to_int()
	if c.begins_with("<"):
		return version < c.substr(1).to_int()
	if c.begins_with("="):
		return version == c.substr(1).to_int()
	return version == c.to_int()


# 判断一个 .ee 是否需要迁移，以及需要迁移多少步。
# 返回值 > 0 表示要迁移；< 0 表示文件来自更新的版本（向前兼容：只警告不迁移）。
static func migration_distance(file_format_version: int) -> int:
	return FORMAT_VERSION - file_format_version
