/**************************************************************************/
/*  block_runner.cpp                                                      */
/**************************************************************************/

#include "block_runner.h"

#include "block_library.h"
#include "block_program.h"
#include "values.h"

#include "core/io/json.h"
#include "core/config/engine.h"
#include "core/io/file_access.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "scene/2d/node_2d.h"

// 单帧单线程的 op 预算：防止String::utf8("不让步的死循环")把程序卡死
static const int MAX_OPS_PER_FRAME = 2000000;
// warp 内超过这个秒数就强制让步（对应 Scratch 的 warp timer）
static const double WARP_TIME_LIMIT = 0.5;

void BlockRunner::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_program", "program"), &BlockRunner::set_program);
	ClassDB::bind_method(D_METHOD("get_program"), &BlockRunner::get_program);
	ClassDB::bind_method(D_METHOD("set_program_json_path", "path"), &BlockRunner::set_program_json_path);
	ClassDB::bind_method(D_METHOD("get_program_json_path"), &BlockRunner::get_program_json_path);
	ClassDB::bind_method(D_METHOD("set_target_path", "path"), &BlockRunner::set_target_path);
	ClassDB::bind_method(D_METHOD("get_target_path"), &BlockRunner::get_target_path);
	ClassDB::bind_method(D_METHOD("set_auto_start", "enabled"), &BlockRunner::set_auto_start);
	ClassDB::bind_method(D_METHOD("is_auto_start"), &BlockRunner::is_auto_start);
	ClassDB::bind_method(D_METHOD("set_debug_print", "enabled"), &BlockRunner::set_debug_print);
	ClassDB::bind_method(D_METHOD("is_debug_print"), &BlockRunner::is_debug_print);
	ClassDB::bind_method(D_METHOD("start"), &BlockRunner::start);
	ClassDB::bind_method(D_METHOD("stop"), &BlockRunner::stop);
	ClassDB::bind_method(D_METHOD("get_errors"), &BlockRunner::get_errors);
	ClassDB::bind_method(D_METHOD("get_warnings"), &BlockRunner::get_warnings);
	ClassDB::bind_method(D_METHOD("get_thread_count"), &BlockRunner::get_thread_count);
	ClassDB::bind_method(D_METHOD("get_time"), &BlockRunner::get_time);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "program", PROPERTY_HINT_RESOURCE_TYPE, "BlockProgram"), "set_program", "get_program");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "program_json_path", PROPERTY_HINT_FILE, "*.json"), "set_program_json_path", "get_program_json_path");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "target_path"), "set_target_path", "get_target_path");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_start"), "set_auto_start", "is_auto_start");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "debug_print"), "set_debug_print", "is_debug_print");
}

// ============================================================ 属性

void BlockRunner::set_program(const Ref<BlockProgram> &p_program) {
	program = p_program;
}

Ref<BlockProgram> BlockRunner::get_program() const {
	return program;
}

void BlockRunner::set_program_json_path(const String &p_path) {
	program_json_path = p_path;
}

String BlockRunner::get_program_json_path() const {
	return program_json_path;
}

void BlockRunner::set_target_path(const NodePath &p_path) {
	target_path = p_path;
}

NodePath BlockRunner::get_target_path() const {
	return target_path;
}

void BlockRunner::set_auto_start(bool p_enabled) {
	auto_start = p_enabled;
}

bool BlockRunner::is_auto_start() const {
	return auto_start;
}

void BlockRunner::set_debug_print(bool p_enabled) {
	debug_print = p_enabled;
}

bool BlockRunner::is_debug_print() const {
	return debug_print;
}

Array BlockRunner::get_errors() const {
	return errors;
}

Array BlockRunner::get_warnings() const {
	return warnings;
}

int BlockRunner::get_thread_count() const {
	return threads.size();
}

double BlockRunner::get_time() const {
	return now;
}

// ============================================================ 生命周期

void BlockRunner::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_READY: {
			// 编辑器里打开场景也会走 _ready，此时绝不能执行积木，
			// 否则在编辑器里编辑角色时它自己就动起来了。
			if (Engine::get_singleton()->is_editor_hint()) {
				break;
			}
			set_process(true);
			if (auto_start) {
				Error err = start();
				if (err != OK) {
					for (int i = 0; i < errors.size(); i++) {
						Dictionary e = errors[i];
						ERR_PRINT("EasyBlocks: " + String(e.get("message", String())));
					}
				}
			}
		} break;
		case NOTIFICATION_PROCESS: {
			_step(get_process_delta_time());
		} break;
		case NOTIFICATION_EXIT_TREE: {
			_clear_threads();
		} break;
	}
}

BlockRunner::BlockRunner() {
	set_process(false);
}

BlockRunner::~BlockRunner() {
	_clear_threads();
}

Error BlockRunner::start() {
	_clear_threads();
	errors.clear();
	warnings.clear();
	now = 0.0;
	frame_count = 0;
	globals.clear();
	global_lists.clear();

	// 程序来源：显式资源优先，其次从 JSON 文件读
	if (program.is_null() && !program_json_path.is_empty()) {
		String text;
		Ref<FileAccess> f = FileAccess::open(program_json_path, FileAccess::READ);
		if (f.is_valid()) {
			text = f->get_as_text();
		} else {
			Dictionary e;
			e["message"] = String::utf8("读不到积木程序文件：") + program_json_path;
			errors.push_back(e);
			return ERR_FILE_NOT_FOUND;
		}
		Ref<BlockProgram> p;
		p.instantiate();
		Error perr = p->set_scripts_json(text);
		if (perr != OK) {
			errors = p->get_errors();
			return perr;
		}
		program = p;
	}

	if (program.is_null()) {
		Dictionary e;
		e["message"] = String::utf8("没有配置积木程序（program 或 program_json_path 都是空的）");
		errors.push_back(e);
		return ERR_UNCONFIGURED;
	}

	Error err = program->compile();
	if (err != OK) {
		errors = program->get_errors();
		return err;
	}

	// 全局变量：从程序里读（scripts 里的 globals 由上层注入到 ir 头部；A1 先空）
	Node *target = _resolve_target(nullptr, "@self");

	Array ir = program->get_ir();
	int started_count = 0;
	for (int i = 0; i < ir.size(); i++) {
		Dictionary hat = ir[i];
		if (String(hat.get("op", String())) != "event.hat") {
			_warn(String::utf8("脚本的第 1 个积木不是帽子积木，忽略"));
			continue;
		}
		Array body = hat.get("body", Array());
		if (body.is_empty()) {
			continue;
		}
		_new_thread(target, body);
		started_count++;
	}

	started = started_count > 0;
	if (debug_print) {
		print_line("EasyBlocks: IR = " + JSON::stringify(ir, "", false, true));
		print_line(vformat(String::utf8("EasyBlocks: 启动 %d 个脚本，目标 %s"), started_count, target ? String(target->get_name()) : String("<none>")));
	}
	return OK;
}

void BlockRunner::stop() {
	for (int i = 0; i < threads.size(); i++) {
		threads[i]->status = THREAD_KILLED;
	}
	_clear_threads();
}

void BlockRunner::_clear_threads() {
	for (int i = 0; i < threads.size(); i++) {
		memdelete(threads[i]);
	}
	threads.clear();
}

BlockRunner::RunnerThread *BlockRunner::_new_thread(Node *p_target, const Array &p_body) {
	RunnerThread *t = memnew(RunnerThread);
	t->target = p_target;
	Frame f;
	f.ops = p_body;
	t->frames.push_back(f);
	threads.push_back(t);
	return t;
}

// ============================================================ 主循环

void BlockRunner::_step(double p_delta) {
	if (threads.is_empty()) {
		return;
	}
	now += p_delta;
	frame_count++;

	// 1. 恢复等待条件已满足的线程
	for (int i = 0; i < threads.size(); i++) {
		RunnerThread *t = threads[i];
		switch (t->status) {
			case THREAD_YIELD_TICK:
				t->status = THREAD_RUNNING;
				break;
			case THREAD_YIELD_TIME:
				if (now >= t->resume_at) {
					t->status = THREAD_RUNNING;
				}
				break;
			case THREAD_YIELD_UNTIL:
				if (EBValues::to_bool(_eval(t, t->wait_cond))) {
					t->status = THREAD_RUNNING;
				}
				break;
			default:
				break;
		}
	}

	// 2. 执行（快照：本帧内新启动的线程留到下一帧）
	Vector<RunnerThread *> snapshot = threads;
	for (int i = 0; i < snapshot.size(); i++) {
		if (snapshot[i]->status == THREAD_RUNNING) {
			_step_thread(snapshot[i]);
		}
	}

	// 3. 回收
	for (int i = threads.size() - 1; i >= 0; i--) {
		RunnerThread *t = threads[i];
		if (t->status == THREAD_DONE || t->status == THREAD_KILLED || t->status == THREAD_ERROR) {
			if (t->status == THREAD_ERROR) {
				errors.push_back(t->error);
			}
			threads.remove_at(i);
			memdelete(t);
		}
	}

	if (debug_print && frame_count % 60 == 0 && !threads.is_empty()) {
		print_line(vformat(String::utf8("EasyBlocks: 帧 %d 线程 %d 时间 %.2fs"), frame_count, threads.size(), now));
	}
}

void BlockRunner::_step_thread(RunnerThread *t) {
	int budget = MAX_OPS_PER_FRAME;
	while (t->status == THREAD_RUNNING) {
		if (--budget <= 0) {
			_warn(String::utf8("单帧执行超出预算，已强制让步（疑似不让步的死循环）"));
			t->status = THREAD_YIELD_TICK;
			return;
		}
		if (t->warp_depth > 0 && (now - t->warp_started) > WARP_TIME_LIMIT) {
			t->warp_started = now;
			t->status = THREAD_YIELD_TICK;
			return;
		}
		if (t->frames.is_empty()) {
			t->status = THREAD_DONE;
			return;
		}

		Frame &f = t->frames.write[t->frames.size() - 1];
		if (f.idx >= f.ops.size()) {
			_close_iteration(t);
			continue;
		}

		Dictionary op = f.ops[f.idx];
		f.idx++;
		t->ops_run++;
		_exec(t, op);
	}
}

void BlockRunner::_close_iteration(RunnerThread *t) {
	if (t->frames.is_empty()) {
		return;
	}
	Frame &f = t->frames.write[t->frames.size() - 1];
	switch (f.loop) {
		case LOOP_SEQ:
			t->frames.remove_at(t->frames.size() - 1);
			break;
		case LOOP_REPEAT:
			f.left--;
			if (f.left > 0) {
				f.idx = 0;
				_loop_yield(t);
			} else {
				t->frames.remove_at(t->frames.size() - 1);
			}
			break;
		case LOOP_FOREVER:
			f.idx = 0;
			_loop_yield(t);
			break;
		case LOOP_WHILE:
			if (EBValues::to_bool(_eval(t, f.cond))) {
				f.idx = 0;
				_loop_yield(t);
			} else {
				t->frames.remove_at(t->frames.size() - 1);
			}
			break;
		case LOOP_WARP:
			t->frames.remove_at(t->frames.size() - 1);
			if (t->warp_depth > 0) {
				t->warp_depth--;
			}
			break;
	}
}

void BlockRunner::_loop_yield(RunnerThread *t) {
	if (t->warp_depth > 0) {
		return; // warp 内不让步
	}
	t->status = THREAD_YIELD_TICK;
}

// ============================================================ 帧栈

void BlockRunner::_push_seq(RunnerThread *t, const Array &p_ops) {
	if (p_ops.is_empty()) {
		return;
	}
	Frame f;
	f.ops = p_ops;
	t->frames.push_back(f);
}

void BlockRunner::_push_loop(RunnerThread *t, int p_kind, const Array &p_ops, int p_count, const Variant &p_cond) {
	if (p_ops.is_empty()) {
		return;
	}
	if (p_kind == LOOP_REPEAT && p_count <= 0) {
		return;
	}
	Frame f;
	f.ops = p_ops;
	f.loop = p_kind;
	f.left = p_count;
	f.cond = p_cond;
	t->frames.push_back(f);
}

void BlockRunner::_push_warp(RunnerThread *t, const Array &p_ops) {
	if (p_ops.is_empty()) {
		return;
	}
	Frame f;
	f.ops = p_ops;
	f.loop = LOOP_WARP;
	t->frames.push_back(f);
}

// ============================================================ 取值

Variant BlockRunner::_eval(RunnerThread *t, const Variant &p_v) {
	if (p_v.get_type() == Variant::DICTIONARY) {
		Dictionary d = p_v;
		if (d.has("op")) {
			return _exec(t, d);
		}
	}
	return p_v;
}

Node *BlockRunner::_resolve_target(RunnerThread *t, const Variant &p_ref) {
	const String ref = String(p_ref);
	if (ref == "@self") {
		if (t != nullptr && t->target != nullptr) {
			return t->target;
		}
		if (!target_path.is_empty()) {
			return get_node_or_null(target_path);
		}
		// 默认：运行器自己就是String::utf8("角色")（测试时省事）；
		// 若它只是挂在角色下面的组件，则用父节点。
		if (get_parent() != nullptr) {
			return get_parent();
		}
		return this;
	}
	if (ref.begins_with("@")) {
		return nullptr; // @stage / @mouse 等在 A2 补
	}
	return get_node_or_null(NodePath(ref));
}

// ============================================================ 变量

Variant BlockRunner::_get_var(const String &p_name, const String &p_scope, RunnerThread *t) {
	if (p_scope == "global") {
		const Variant *v = globals.getptr(p_name);
		return v ? *v : Variant(0);
	}
	const Variant *v = globals.getptr(p_name);
	return v ? *v : Variant(0);
}

void BlockRunner::_set_var(const String &p_name, const Variant &p_value, const String &p_scope, RunnerThread *t) {
	globals[p_name] = p_value;
}

Array BlockRunner::_get_list(const String &p_name, const String &p_scope, RunnerThread *t) {
	Array *a = global_lists.getptr(p_name);
	if (a == nullptr) {
		global_lists[p_name] = Array();
		a = global_lists.getptr(p_name);
	}
	return *a;
}

void BlockRunner::_warn(const String &p_msg) {
	if (warnings.size() < 200) {
		warnings.push_back(p_msg);
	}
	if (debug_print) {
		print_line(String::utf8("EasyBlocks 警告: ") + p_msg);
	}
}

void BlockRunner::_fail(RunnerThread *t, const String &p_msg) {
	t->status = THREAD_ERROR;
	t->error = p_msg;
}

// ============================================================ op 派发

Variant BlockRunner::_exec(RunnerThread *t, const Dictionary &p_op) {
	const String op_id = p_op.get("op", String());
	if (op_id.is_empty()) {
		return Variant();
	}
	if (debug_print && trace_count < 40) {
		trace_count++;
		print_line("EasyBlocks: op " + op_id);
	}

	auto arg = [&](const char *k) -> Variant { return _eval(t, p_op.get(k, Variant())); };
	auto num = [&](const char *k) -> double { return EBValues::to_number(arg(k)); };
	auto str = [&](const char *k) -> String { return EBValues::to_string(arg(k)); };

	Node *target = _resolve_target(t, p_op.get("target", Variant("@self")));

	// ---- 控制流（在调度器语义里，不在 op 表里）----
	if (op_id == "control.repeat") {
		_push_loop(t, LOOP_REPEAT, p_op.get("body", Array()), EBValues::to_int(arg("times")), Variant());
		return Variant();
	}
	if (op_id == "control.forever") {
		_push_loop(t, LOOP_FOREVER, p_op.get("body", Array()), 0, Variant());
		return Variant();
	}
	if (op_id == "control.while") {
		_push_loop(t, LOOP_WHILE, p_op.get("body", Array()), 0, p_op.get("cond", Variant()));
		return Variant();
	}
	if (op_id == "control.if") {
		if (EBValues::to_bool(arg("cond"))) {
			_push_seq(t, p_op.get("body", Array()));
		}
		return Variant();
	}
	if (op_id == "control.if_else") {
		if (EBValues::to_bool(arg("cond"))) {
			_push_seq(t, p_op.get("then", Array()));
		} else {
			_push_seq(t, p_op.get("else", Array()));
		}
		return Variant();
	}
	if (op_id == "control.wait") {
		double secs = num("seconds");
		if (secs <= 0.0) {
			t->status = THREAD_YIELD_TICK;
		} else {
			t->status = THREAD_YIELD_TIME;
			t->resume_at = now + secs;
		}
		return Variant();
	}
	if (op_id == "control.wait_until") {
		t->status = THREAD_YIELD_UNTIL;
		t->wait_cond = p_op.get("cond", Variant());
		return Variant();
	}
	if (op_id == "control.stop_all") {
		for (int i = 0; i < threads.size(); i++) {
			threads[i]->status = THREAD_KILLED;
		}
		return Variant();
	}
	if (op_id == "control.stop") {
		String mode = str("mode");
		if (mode == "all") {
			for (int i = 0; i < threads.size(); i++) {
				threads[i]->status = THREAD_KILLED;
			}
		} else {
			t->status = THREAD_DONE;
		}
		return Variant();
	}
	if (op_id == "control.warp") {
		t->warp_depth++;
		t->warp_started = now;
		_push_warp(t, p_op.get("body", Array()));
		return Variant();
	}

	// ---- 运动 ----
	if (op_id == "motion.set_position") {
		if (Node2D *n2 = Object::cast_to<Node2D>(target)) {
			n2->set_position(Vector2(num("x"), num("y")));
		}
		return Variant();
	}
	if (op_id == "motion.change_x") {
		if (Node2D *n2 = Object::cast_to<Node2D>(target)) {
			n2->set_position(n2->get_position() + Vector2(num("dx"), 0));
		}
		return Variant();
	}
	if (op_id == "motion.change_y") {
		if (Node2D *n2 = Object::cast_to<Node2D>(target)) {
			n2->set_position(n2->get_position() + Vector2(0, num("dy")));
		}
		return Variant();
	}
	if (op_id == "motion.set_x") {
		if (Node2D *n2 = Object::cast_to<Node2D>(target)) {
			n2->set_position(Vector2(num("x"), n2->get_position().y));
		}
		return Variant();
	}
	if (op_id == "motion.set_y") {
		if (Node2D *n2 = Object::cast_to<Node2D>(target)) {
			n2->set_position(Vector2(n2->get_position().x, num("y")));
		}
		return Variant();
	}
	if (op_id == "motion.move_steps") {
		if (Node2D *n2 = Object::cast_to<Node2D>(target)) {
			n2->set_position(n2->get_position() + Vector2(1, 0).rotated(n2->get_rotation()) * num("steps"));
		}
		return Variant();
	}
	if (op_id == "motion.get_x") {
		if (Node2D *n2 = Object::cast_to<Node2D>(target)) {
			return n2->get_position().x;
		}
		return Variant(0);
	}
	if (op_id == "motion.get_y") {
		if (Node2D *n2 = Object::cast_to<Node2D>(target)) {
			return n2->get_position().y;
		}
		return Variant(0);
	}
	if (op_id == "motion.point_direction") {
		if (Node2D *n2 = Object::cast_to<Node2D>(target)) {
			n2->set_rotation(Math::deg_to_rad(num("direction") - 90.0));
		}
		return Variant();
	}
	if (op_id == "motion.get_direction") {
		if (Node2D *n2 = Object::cast_to<Node2D>(target)) {
			return Math::rad_to_deg(n2->get_rotation()) + 90.0;
		}
		return Variant(0);
	}

	// ---- 外观 ----
	if (op_id == "looks.set_visible") {
		if (CanvasItem *ci = Object::cast_to<CanvasItem>(target)) {
			ci->set_visible(EBValues::to_bool(arg("visible")));
		}
		return Variant();
	}

	// ---- 变量 ----
	if (op_id == "var.get") {
		return _get_var(str("name"), str("scope"), t);
	}
	if (op_id == "var.set") {
		_set_var(str("name"), arg("value"), str("scope"), t);
		return Variant();
	}
	if (op_id == "var.change") {
		const String name = str("name");
		const String scope = str("scope");
		Variant cur = _get_var(name, scope, t);
		_set_var(name, EBValues::to_number(cur) + num("delta"), scope, t);
		return Variant();
	}

	// ---- 运算 ----
	if (op_id == "op.add") {
		return EBValues::add(arg("left"), arg("right"));
	}
	if (op_id == "op.sub") {
		return EBValues::to_number(arg("left")) - EBValues::to_number(arg("right"));
	}
	if (op_id == "op.mul") {
		return EBValues::to_number(arg("left")) * EBValues::to_number(arg("right"));
	}
	if (op_id == "op.div") {
		const double d = EBValues::to_number(arg("right"));
		const double n = EBValues::to_number(arg("left"));
		if (d == 0.0) {
			if (n == 0.0) {
				return Math::NaN;
			}
			return n > 0 ? Math::INF : -Math::INF;
		}
		return n / d;
	}
	if (op_id == "op.mod") {
		const double y = EBValues::to_number(arg("right"));
		if (y == 0.0) {
			return Math::NaN;
		}
		return Math::fmod(EBValues::to_number(arg("left")), y);
	}
	if (op_id == "op.round") {
		const double n = EBValues::to_number(arg("value"));
		return n >= 0 ? Math::floor(n + 0.5) : Math::ceil(n - 0.5);
	}
	if (op_id == "op.abs") {
		return Math::abs(EBValues::to_number(arg("value")));
	}
	if (op_id == "op.gt") {
		return EBValues::compare(arg("left"), arg("right")) > 0;
	}
	if (op_id == "op.lt") {
		return EBValues::compare(arg("left"), arg("right")) < 0;
	}
	if (op_id == "op.eq") {
		return EBValues::equals(arg("left"), arg("right"));
	}
	if (op_id == "op.and") {
		return EBValues::to_bool(arg("left")) && EBValues::to_bool(arg("right"));
	}
	if (op_id == "op.or") {
		return EBValues::to_bool(arg("left")) || EBValues::to_bool(arg("right"));
	}
	if (op_id == "op.not") {
		return !EBValues::to_bool(arg("value"));
	}
	if (op_id == "op.join") {
		return EBValues::to_string(arg("left")) + EBValues::to_string(arg("right"));
	}
	if (op_id == "op.random") {
		const double a = EBValues::to_number(arg("from"));
		const double b = EBValues::to_number(arg("to"));
		const double lo = MIN(a, b);
		const double hi = MAX(a, b);
		if (a == Math::floor(a) && b == Math::floor(b)) {
			const int l = (int)lo;
			const int h = (int)hi;
			// Math 里没有 randi_range，自己算（闭区间）
			return double(l + int(Math::rand() % uint32_t(h - l + 1)));
		}
		return lo + Math::randf() * (hi - lo);
	}

	// ---- 还没实现的：明确告警一次，不静默 ----
	_warn(String::utf8("这个 op 在 A1 阶段还没实现：") + op_id);
	return Variant();
}
